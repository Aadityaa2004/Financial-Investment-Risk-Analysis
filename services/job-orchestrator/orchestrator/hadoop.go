package orchestrator

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Registry holds all known job definitions and their runtime states.
type Registry struct {
	mu         sync.RWMutex
	definitions map[string]JobDefinition
	states      map[string]*JobState // keyed by RunID
	cfg         HadoopConfig
}

// HadoopConfig captures environment-derived Hadoop settings.
type HadoopConfig struct {
	Home          string
	NameNode      string
	HDFSInput     string
	HDFSOutputBase string
	MapReduceDir  string
}

// NewRegistry builds a Registry pre-loaded with the four job definitions.
func NewRegistry(cfg HadoopConfig) *Registry {
	defs := map[string]JobDefinition{
		"job1": {
			ID:          "job1",
			Name:        "Default Rate by Loan Grade",
			Description: "Calculates default rate percentage for each loan grade A-G",
			MapperPath:  filepath.Join(cfg.MapReduceDir, "job1-default-by-grade", "mapper.py"),
			ReducerPath: filepath.Join(cfg.MapReduceDir, "job1-default-by-grade", "reducer.py"),
			OutputDir:   cfg.HDFSOutputBase + "/job1-grade",
		},
		"job2": {
			ID:          "job2",
			Name:        "Default Rate by US State",
			Description: "Calculates default rate percentage per US state",
			MapperPath:  filepath.Join(cfg.MapReduceDir, "job2-default-by-state", "mapper.py"),
			ReducerPath: filepath.Join(cfg.MapReduceDir, "job2-default-by-state", "reducer.py"),
			OutputDir:   cfg.HDFSOutputBase + "/job2-state",
		},
		"job3": {
			ID:          "job3",
			Name:        "Default Rate by Employment Length",
			Description: "Calculates default rate percentage per employment-length bucket",
			MapperPath:  filepath.Join(cfg.MapReduceDir, "job3-default-by-employment", "mapper.py"),
			ReducerPath: filepath.Join(cfg.MapReduceDir, "job3-default-by-employment", "reducer.py"),
			OutputDir:   cfg.HDFSOutputBase + "/job3-employment",
		},
		"job4": {
			ID:          "job4",
			Name:        "Interest Rate vs Default Rate",
			Description: "Computes avg interest rate and default rate per grade (risk-return tradeoff)",
			MapperPath:  filepath.Join(cfg.MapReduceDir, "job4-interest-vs-default", "mapper.py"),
			ReducerPath: filepath.Join(cfg.MapReduceDir, "job4-interest-vs-default", "reducer.py"),
			OutputDir:   cfg.HDFSOutputBase + "/job4-interest",
		},
	}
	return &Registry{
		definitions: defs,
		states:      make(map[string]*JobState),
		cfg:         cfg,
	}
}

// Definitions returns all job definitions (thread-safe).
func (r *Registry) Definitions() []JobDefinition {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]JobDefinition, 0, len(r.definitions))
	for _, d := range r.definitions {
		out = append(out, d)
	}
	return out
}

// GetState returns the current state for a run ID.
func (r *Registry) GetState(runID string) (*JobState, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	s, ok := r.states[runID]
	return s, ok
}

// Submit launches the requested jobs asynchronously and returns their initial states.
func (r *Registry) Submit(ctx context.Context, jobIDs []string) (string, []*JobState, error) {
	runID := uuid.New().String()

	// Expand "all" alias
	if len(jobIDs) == 1 && jobIDs[0] == "all" {
		jobIDs = []string{"job1", "job2", "job3", "job4"}
	}

	var states []*JobState
	r.mu.Lock()
	for _, id := range jobIDs {
		def, ok := r.definitions[id]
		if !ok {
			r.mu.Unlock()
			return "", nil, fmt.Errorf("unknown job id: %q", id)
		}
		state := &JobState{
			RunID:     runID + ":" + id,
			JobID:     def.ID,
			Status:    StatusPending,
			StartedAt: time.Now(),
		}
		r.states[state.RunID] = state
		states = append(states, state)
	}
	r.mu.Unlock()

	// Run jobs sequentially in background (Streaming jobs share cluster resources)
	go func() {
		for i, state := range states {
			def := r.definitions[jobIDs[i]]
			r.runJob(ctx, state, def)
		}
	}()

	return runID, states, nil
}

// runJob executes a single Hadoop Streaming job via os/exec and updates state.
func (r *Registry) runJob(ctx context.Context, state *JobState, def JobDefinition) {
	r.setStatus(state, StatusRunning, "")

	streamingJar, err := findStreamingJar(r.cfg.Home)
	if err != nil {
		r.setStatus(state, StatusFailed, err.Error())
		return
	}

	// Remove stale output directory (ignore error — it may not exist)
	_ = hdfsRemove(def.OutputDir)

	args := []string{
		"jar", streamingJar,
		"-D", "mapreduce.job.name=RiskAnalysis-" + def.ID,
		"-D", "mapreduce.job.reduces=1",
		"-input", r.cfg.HDFSInput,
		"-output", def.OutputDir,
		"-mapper", "python3 mapper.py",
		"-reducer", "python3 reducer.py",
		"-file", def.MapperPath,
		"-file", def.ReducerPath,
	}

	cmd := exec.CommandContext(ctx, "hadoop", args...)
	cmd.Env = append(os.Environ(),
		"HADOOP_HOME="+r.cfg.Home,
		"JAVA_HOME="+os.Getenv("JAVA_HOME"),
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	cmd.Stdout = os.Stdout

	slog.Info("launching hadoop job", "job_id", def.ID, "output", def.OutputDir)
	if err := cmd.Run(); err != nil {
		errMsg := fmt.Sprintf("hadoop exit: %v; stderr: %s", err, stderr.String())
		slog.Error("job failed", "job_id", def.ID, "err", errMsg)
		r.setStatus(state, StatusFailed, errMsg)
		return
	}

	// Extract YARN application ID from stderr for logging
	if appID := extractYARNAppID(stderr.String()); appID != "" {
		r.mu.Lock()
		state.YARNAppID = appID
		r.mu.Unlock()
	}

	r.setStatus(state, StatusCompleted, "")
	slog.Info("job completed", "job_id", def.ID)
}

func (r *Registry) setStatus(state *JobState, status JobStatus, errMsg string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	state.Status = status
	state.Error = errMsg
	if status == StatusCompleted || status == StatusFailed {
		state.CompletedAt = time.Now()
	}
}

// findStreamingJar locates the hadoop-streaming jar inside HADOOP_HOME.
func findStreamingJar(hadoopHome string) (string, error) {
	pattern := filepath.Join(hadoopHome, "share", "hadoop", "tools", "lib", "hadoop-streaming-*.jar")
	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) == 0 {
		return "", fmt.Errorf("hadoop-streaming jar not found at %s", pattern)
	}
	return matches[0], nil
}

// hdfsRemove deletes an HDFS path via the CLI (ignores failure).
func hdfsRemove(path string) error {
	cmd := exec.Command("hdfs", "dfs", "-rm", "-r", "-f", path)
	return cmd.Run()
}

// extractYARNAppID parses the YARN application ID from Hadoop stderr output.
func extractYARNAppID(stderr string) string {
	for _, line := range strings.Split(stderr, "\n") {
		if strings.Contains(line, "application_") {
			fields := strings.Fields(line)
			for _, f := range fields {
				if strings.HasPrefix(f, "application_") {
					return f
				}
			}
		}
	}
	return ""
}

// ReadHDFSFile fetches a file from HDFS via the WebHDFS REST API.
func ReadHDFSFile(namenode, path string) ([]byte, error) {
	url := fmt.Sprintf("http://%s:9870/webhdfs/v1%s?op=OPEN", namenode, path)
	resp, err := http.Get(url) //nolint:gosec
	if err != nil {
		return nil, fmt.Errorf("webhdfs GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("webhdfs returned HTTP %d for %s", resp.StatusCode, path)
	}
	return io.ReadAll(resp.Body)
}

// FileStatus is a single entry from WebHDFS LISTSTATUS.
type FileStatus struct {
	PathSuffix string `json:"pathSuffix"`
	Type       string `json:"type"`
	Length     int64  `json:"length"`
}

// ListHDFSDir returns the file listing for an HDFS directory via WebHDFS.
func ListHDFSDir(namenode, dirPath string) ([]FileStatus, error) {
	url := fmt.Sprintf("http://%s:9870/webhdfs/v1%s?op=LISTSTATUS", namenode, dirPath)
	resp, err := http.Get(url) //nolint:gosec
	if err != nil {
		return nil, fmt.Errorf("webhdfs LISTSTATUS: %w", err)
	}
	defer resp.Body.Close()

	var envelope struct {
		FileStatuses struct {
			FileStatus []FileStatus `json:"FileStatus"`
		} `json:"FileStatuses"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		return nil, fmt.Errorf("decoding LISTSTATUS: %w", err)
	}
	return envelope.FileStatuses.FileStatus, nil
}
