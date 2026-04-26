package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func orchestratorURL() string {
	host := os.Getenv("ORCHESTRATOR_HOST")
	if host == "" {
		host = "localhost"
	}
	port := os.Getenv("ORCHESTRATOR_PORT")
	if port == "" {
		port = "8081"
	}
	return fmt.Sprintf("http://%s:%s", host, port)
}

func proxyGet(url string) ([]byte, int, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url) //nolint:gosec
	if err != nil {
		return nil, http.StatusServiceUnavailable, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return body, resp.StatusCode, nil
}

func proxyPost(url string, payload any) ([]byte, int, error) {
	buf, err := json.Marshal(payload)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", bytes.NewReader(buf)) //nolint:gosec
	if err != nil {
		return nil, http.StatusServiceUnavailable, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return body, resp.StatusCode, nil
}

// ListJobsHandler returns all defined MapReduce jobs.
func ListJobsHandler(c *gin.Context) {
	body, status, err := proxyGet(orchestratorURL() + "/jobs")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "orchestrator unavailable: " + err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// RunJobsHandler accepts {"job_ids": ["job1","job2",...]} and submits them.
func RunJobsHandler(c *gin.Context) {
	var req struct {
		JobIDs []string `json:"job_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	body, status, err := proxyPost(orchestratorURL()+"/jobs/run", req)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "orchestrator unavailable: " + err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// JobStatusHandler returns the status of a specific run_id:job_id combination.
func JobStatusHandler(c *gin.Context) {
	runID := c.Param("run_id")
	body, status, err := proxyGet(orchestratorURL() + "/jobs/" + runID + "/status")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "orchestrator unavailable: " + err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}
