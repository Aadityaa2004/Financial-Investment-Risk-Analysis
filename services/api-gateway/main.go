// Package main runs the API Gateway service.
// It is the single entry point for external clients, routing requests to the
// job orchestrator and result aggregator via HTTP proxying.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/aadityaa/hadoop-risk/api-gateway/handlers"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(requestLogger())
	r.Use(corsMiddleware())

	// Health
	r.GET("/health", handlers.HealthHandler)

	// Jobs
	api := r.Group("/api")
	{
		api.GET("/jobs", handlers.ListJobsHandler)
		api.POST("/jobs/run", handlers.RunJobsHandler)
		api.GET("/jobs/:run_id/status", handlers.JobStatusHandler)

		// Results
		api.GET("/results/grade", handlers.GradeResultsHandler)
		api.GET("/results/state", handlers.StateResultsHandler)
		api.GET("/results/employment", handlers.EmploymentResultsHandler)
		api.GET("/results/interest", handlers.InterestResultsHandler)
		api.GET("/results/risk-summary", handlers.RiskSummaryHandler)
	}

	port := os.Getenv("API_GATEWAY_PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		slog.Info("api-gateway starting", "port", port)
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
	slog.Info("api-gateway shutting down")
	_ = server.Shutdown(ctx)
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type,Authorization")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func requestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		slog.Info("request",
			"method", c.Request.Method,
			"path", c.Request.URL.Path,
			"status", c.Writer.Status(),
			"latency_ms", time.Since(start).Milliseconds(),
		)
	}
}
