# Multi-stage build for Stratium Node
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git make

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the stratiumd binary
RUN CGO_ENABLED=0 GOOS=linux go build -o stratiumd ./cmd/stratiumd/main.go

# Runtime stage
FROM alpine:latest

WORKDIR /root

# Install runtime dependencies
RUN apk add --no-cache ca-certificates bash curl jq

# Copy binary from builder
COPY --from=builder /app/stratiumd /usr/local/bin/stratiumd

# Create stratium home directory
RUN mkdir -p .stratium

# Expose ports
EXPOSE 26656 26657 26660 1317

ENTRYPOINT ["stratiumd"]