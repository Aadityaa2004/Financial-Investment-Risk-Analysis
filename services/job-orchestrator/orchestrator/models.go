// Package orchestrator manages the lifecycle of Hadoop MapReduce jobs.
package orchestrator

import "time"

// JobStatus represents the current state of a MapReduce job.
type JobStatus string

const (
	StatusPending   JobStatus = "PENDING"
	StatusRunning   JobStatus = "RUNNING"
	StatusCompleted JobStatus = "COMPLETED"
	StatusFailed    JobStatus = "FAILED"
)

// JobDefinition describes a MapReduce job that can be submitted.
type JobDefinition struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	MapperPath  string `json:"mapper_path"`
	ReducerPath string `json:"reducer_path"`
	OutputDir   string `json:"output_dir"`
}

// JobState tracks the runtime state of a submitted job.
type JobState struct {
	RunID       string    `json:"run_id"`
	JobID       string    `json:"job_id"`
	Status      JobStatus `json:"status"`
	StartedAt   time.Time `json:"started_at"`
	CompletedAt time.Time `json:"completed_at,omitempty"`
	Error       string    `json:"error,omitempty"`
	YARNAppID   string    `json:"yarn_app_id,omitempty"`
}

// RunRequest is the body of POST /jobs/run.
type RunRequest struct {
	JobIDs []string `json:"job_ids"`
}

// RunResponse is the response to POST /jobs/run.
type RunResponse struct {
	RunID  string      `json:"run_id"`
	Jobs   []*JobState `json:"jobs"`
}
