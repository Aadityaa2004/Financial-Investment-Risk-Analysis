# Dashboard — standalone image for development/testing.
# In production the binary is built inside Dockerfile.master.
FROM golang:1.22.4-alpine3.20 AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY dashboard/ ./dashboard/
RUN go build -ldflags="-s -w" -o /dashboard ./dashboard/

FROM alpine:3.20
RUN addgroup -S hadoop && adduser -S hadoop -G hadoop
COPY --from=builder /dashboard /usr/local/bin/dashboard
USER hadoop
EXPOSE 3000
CMD ["/usr/local/bin/dashboard"]
