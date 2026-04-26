# API Gateway — standalone image for development/testing outside the master container.
# In production the binary is built inside Dockerfile.master.
FROM golang:1.22.4-alpine3.20 AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY api-gateway/ ./api-gateway/
RUN go build -ldflags="-s -w" -o /api-gateway ./api-gateway/

FROM alpine:3.20
RUN addgroup -S hadoop && adduser -S hadoop -G hadoop
COPY --from=builder /api-gateway /usr/local/bin/api-gateway
USER hadoop
EXPOSE 8080
CMD ["/usr/local/bin/api-gateway"]
