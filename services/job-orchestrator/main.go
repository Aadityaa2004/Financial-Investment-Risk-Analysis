// Package main runs the Job Orchestrator service.
// It exposes a simple HTTP API that submits Hadoop Streaming jobs to YARN
// and tracks their status in a thread-safe in-memory registry.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aadityaa/hadoop-risk/job-orchestrator/orchestrator"
)

func loadConfig() orchestrator.HadoopConfig {
	hadoopHome := os.Getenv("HADOOP_HOME")
	if hadoopHome == "" {
		hadoopHome = "/opt/hadoop"
	}
	nameNode := os.Getenv("HADOOP_NAMENODE_HOST")
	if nameNode == "" {
		nameNode = "master"
	}
	hdfsInput := os.Getenv("HDFS_INPUT")
	if hdfsInput == "" {
		hdfsInput = "/user/hadoop/lendingclub/input"
	}
	hdfsBase := os.Getenv("HDFS_OUTPUT_BASE")
	if hdfsBase == "" {
		hdfsBase = "/user/hadoop/lendingclub/output"
	}
	mrDir := os.Getenv("MAPREDUCE_DIR")
	if mrDir == "" {
		mrDir = "/mapreduce"
	}
	return orchestrator.HadoopConfig{
		Home:           hadoopHome,
		NameNode:       nameNode,
		HDFSInput:      hdfsInput,
		HDFSOutputBase: hdfsBase,
		MapReduceDir:   mrDir,
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func buildMux(reg *orchestrator.Registry) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// GET /jobs — list all defined jobs
	mux.HandleFunc("GET /jobs", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, reg.Definitions())
	})

	// POST /jobs/run — submit one or more jobs
	mux.HandleFunc("POST /jobs/run", func(w http.ResponseWriter, r *http.Request) {
		var req orchestrator.RunRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
			return
		}
		if len(req.JobIDs) == 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_ids must not be empty"})
			return
		}

		ctx := context.Background()
		runID, states, err := reg.Submit(ctx, req.JobIDs)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusAccepted, orchestrator.RunResponse{RunID: runID, Jobs: states})
	})

	// GET /jobs/{run_id}/status — get status of all jobs in a run
	mux.HandleFunc("GET /jobs/", func(w http.ResponseWriter, r *http.Request) {
		// path: /jobs/<runID>/status  or  /jobs/<runID>:<jobID>/status
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		if len(parts) < 2 {
			http.NotFound(w, r)
			return
		}
		runID := parts[1]
		state, ok := reg.GetState(runID)
		if !ok {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "run_id not found"})
			return
		}
		writeJSON(w, http.StatusOK, state)
	})

	return mux
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := loadConfig()
	reg := orchestrator.NewRegistry(cfg)

	port := os.Getenv("ORCHESTRATOR_PORT")
	if port == "" {
		port = "8081"
	}

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      buildMux(reg),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 0, // jobs can run for many minutes
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		slog.Info("job-orchestrator starting", "port", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	slog.Info("job-orchestrator shutting down")
	_ = server.Shutdown(ctx)
}
