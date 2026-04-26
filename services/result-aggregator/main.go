// Package main implements the Result Aggregator service.
// It fetches raw MapReduce output from HDFS via WebHDFS and exposes
// parsed, structured JSON through an HTTP API consumed by the API gateway.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"sort"

	"github.com/aadityaa/hadoop-risk/result-aggregator/models"
	"github.com/aadityaa/hadoop-risk/result-aggregator/parsers"
)

type config struct {
	namenode string
	webPort  string
	basePath string
}

func loadConfig() config {
	namenode := os.Getenv("HADOOP_NAMENODE_HOST")
	if namenode == "" {
		namenode = "master"
	}
	port := os.Getenv("AGGREGATOR_PORT")
	if port == "" {
		port = "8082"
	}
	base := os.Getenv("HDFS_OUTPUT_BASE")
	if base == "" {
		base = "/user/hadoop/lendingclub/output"
	}
	return config{namenode: namenode, webPort: port, basePath: base}
}

// fetchHDFSFile reads a file from HDFS via the WebHDFS REST API.
func fetchHDFSFile(namenode, path string) (string, error) {
	url := fmt.Sprintf("http://%s:9870/webhdfs/v1%s?op=OPEN", namenode, path)
	resp, err := http.Get(url) //nolint:gosec
	if err != nil {
		return "", fmt.Errorf("webhdfs GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("webhdfs %s returned HTTP %d", path, resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading webhdfs response: %w", err)
	}
	return string(body), nil
}

// listHDFSDir lists files in an HDFS directory and returns their paths.
func listHDFSDir(namenode, dirPath string) ([]string, error) {
	url := fmt.Sprintf("http://%s:9870/webhdfs/v1%s?op=LISTSTATUS", namenode, dirPath)
	resp, err := http.Get(url) //nolint:gosec
	if err != nil {
		return nil, fmt.Errorf("webhdfs LISTSTATUS %s: %w", dirPath, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("webhdfs LISTSTATUS %s returned HTTP %d", dirPath, resp.StatusCode)
	}

	var listing struct {
		FileStatuses struct {
			FileStatus []struct {
				PathSuffix string `json:"pathSuffix"`
				Type       string `json:"type"`
			} `json:"FileStatus"`
		} `json:"FileStatuses"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&listing); err != nil {
		return nil, fmt.Errorf("decoding LISTSTATUS: %w", err)
	}

	var paths []string
	for _, fs := range listing.FileStatuses.FileStatus {
		if fs.Type == "FILE" && fs.PathSuffix != "_SUCCESS" {
			paths = append(paths, dirPath+"/"+fs.PathSuffix)
		}
	}
	return paths, nil
}

// readJobOutput concatenates all part files from an HDFS output directory.
func readJobOutput(namenode, jobDir string) (string, error) {
	files, err := listHDFSDir(namenode, jobDir)
	if err != nil {
		return "", err
	}
	var combined string
	for _, f := range files {
		content, err := fetchHDFSFile(namenode, f)
		if err != nil {
			slog.Warn("skipping file", "path", f, "err", err)
			continue
		}
		combined += content + "\n"
	}
	return combined, nil
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("json encode error", "err", err)
	}
}

func makeHandlers(cfg config) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /internal/results/grade", func(w http.ResponseWriter, _ *http.Request) {
		raw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job1-grade")
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		results, err := parsers.ParseGradeResults(raw)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, results)
	})

	mux.HandleFunc("GET /internal/results/state", func(w http.ResponseWriter, _ *http.Request) {
		raw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job2-state")
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		results, err := parsers.ParseStateResults(raw)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, results)
	})

	mux.HandleFunc("GET /internal/results/employment", func(w http.ResponseWriter, _ *http.Request) {
		raw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job3-employment")
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		results, err := parsers.ParseEmploymentResults(raw)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, results)
	})

	mux.HandleFunc("GET /internal/results/interest", func(w http.ResponseWriter, _ *http.Request) {
		raw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job4-interest")
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		results, err := parsers.ParseInterestResults(raw)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, results)
	})

	mux.HandleFunc("GET /internal/results/risk-summary", func(w http.ResponseWriter, _ *http.Request) {
		summary, err := buildRiskSummary(cfg)
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, summary)
	})

	return mux
}

func buildRiskSummary(cfg config) (*models.RiskSummary, error) {
	gradeRaw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job1-grade")
	if err != nil {
		return nil, fmt.Errorf("job1: %w", err)
	}
	grades, err := parsers.ParseGradeResults(gradeRaw)
	if err != nil {
		return nil, err
	}

	stateRaw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job2-state")
	if err != nil {
		return nil, fmt.Errorf("job2: %w", err)
	}
	states, err := parsers.ParseStateResults(stateRaw)
	if err != nil {
		return nil, err
	}

	empRaw, err := readJobOutput(cfg.namenode, cfg.basePath+"/job3-employment")
	if err != nil {
		return nil, fmt.Errorf("job3: %w", err)
	}
	employment, err := parsers.ParseEmploymentResults(empRaw)
	if err != nil {
		return nil, err
	}

	sort.Slice(grades, func(i, j int) bool { return grades[i].DefaultRate > grades[j].DefaultRate })
	sort.Slice(states, func(i, j int) bool { return states[i].DefaultRate > states[j].DefaultRate })
	sort.Slice(employment, func(i, j int) bool { return employment[i].DefaultRate > employment[j].DefaultRate })

	summary := &models.RiskSummary{}

	if len(grades) > 0 {
		summary.HighestRiskGrade = grades[0].Grade
		summary.LowestRiskGrade = grades[len(grades)-1].Grade
		var totalLoans, totalDefaults int
		for _, g := range grades {
			totalLoans += g.TotalLoans
			totalDefaults += g.Defaults
		}
		summary.TotalLoansAnalyzed = totalLoans
		if totalLoans > 0 {
			summary.OverallDefaultRate = float64(totalDefaults) / float64(totalLoans) * 100
		}
	}
	if len(states) > 0 {
		summary.HighestRiskState = states[0].State
	}
	if len(employment) > 0 {
		summary.HighestRiskEmpBucket = employment[0].Bucket
	}

	summary.Recommendation = fmt.Sprintf(
		"Based on %d loans analyzed: avoid Grade %s loans (%.1f%% default rate). "+
			"Grade %s loans offer the best risk-adjusted returns. "+
			"Borrowers with %s employment history carry the highest default risk.",
		summary.TotalLoansAnalyzed,
		summary.HighestRiskGrade,
		grades[0].DefaultRate,
		summary.LowestRiskGrade,
		summary.HighestRiskEmpBucket,
	)

	return summary, nil
}

func main() {
	cfg := loadConfig()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	mux := makeHandlers(cfg)
	addr := ":" + cfg.webPort
	slog.Info("result-aggregator starting", "addr", addr, "namenode", cfg.namenode)

	server := &http.Server{Addr: addr, Handler: mux}
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", "err", err)
		os.Exit(1)
	}
}
