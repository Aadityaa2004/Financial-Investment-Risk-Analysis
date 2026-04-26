// Package handlers contains the Gin route handlers for the API gateway.
package handlers

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

// HealthHandler returns the health of the gateway and connectivity to the NameNode.
func HealthHandler(c *gin.Context) {
	namenode := os.Getenv("HADOOP_NAMENODE_HOST")
	if namenode == "" {
		namenode = "master"
	}

	namenodeStatus := "reachable"
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://%s:9870/webhdfs/v1/?op=LISTSTATUS", namenode))
	if err != nil || resp.StatusCode >= 500 {
		namenodeStatus = "unreachable"
	}
	if resp != nil {
		resp.Body.Close()
	}

	c.JSON(http.StatusOK, gin.H{
		"status":             "ok",
		"hadoop_namenode":    namenodeStatus,
		"service":            "api-gateway",
		"timestamp":          time.Now().UTC(),
	})
}
