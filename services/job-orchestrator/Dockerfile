# Job Orchestrator — standalone image for development/testing.
# In production the binary is built inside Dockerfile.master.
FROM golang:1.22.4-alpine3.20 AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY job-orchestrator/ ./job-orchestrator/
RUN go build -ldflags="-s -w" -o /job-orchestrator ./job-orchestrator/

FROM alpine:3.20
RUN addgroup -S hadoop && adduser -S hadoop -G hadoop
COPY --from=builder /job-orchestrator /usr/local/bin/job-orchestrator
USER hadoop
EXPOSE 8081
CMD ["/usr/local/bin/job-orchestrator"]
