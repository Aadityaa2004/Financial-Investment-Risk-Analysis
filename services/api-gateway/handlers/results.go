package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func aggregatorURL() string {
	host := os.Getenv("AGGREGATOR_HOST")
	if host == "" {
		host = "localhost"
	}
	port := os.Getenv("AGGREGATOR_PORT")
	if port == "" {
		port = "8082"
	}
	return fmt.Sprintf("http://%s:%s", host, port)
}

func fetchAggregator(path string) ([]byte, int, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(aggregatorURL() + path) //nolint:gosec
	if err != nil {
		return nil, http.StatusServiceUnavailable, fmt.Errorf("aggregator unavailable: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return body, resp.StatusCode, nil
}

// GradeResultsHandler proxies Job 1 output (default rate by loan grade).
func GradeResultsHandler(c *gin.Context) {
	body, status, err := fetchAggregator("/internal/results/grade")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// StateResultsHandler proxies Job 2 output (default rate by US state).
func StateResultsHandler(c *gin.Context) {
	body, status, err := fetchAggregator("/internal/results/state")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// EmploymentResultsHandler proxies Job 3 output (default rate by employment).
func EmploymentResultsHandler(c *gin.Context) {
	body, status, err := fetchAggregator("/internal/results/employment")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// InterestResultsHandler proxies Job 4 output (interest vs default by grade).
func InterestResultsHandler(c *gin.Context) {
	body, status, err := fetchAggregator("/internal/results/interest")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}

// RiskSummaryHandler proxies the aggregated cross-job risk summary.
func RiskSummaryHandler(c *gin.Context) {
	body, status, err := fetchAggregator("/internal/results/risk-summary")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()})
		return
	}
	c.Data(status, "application/json", body)
}
