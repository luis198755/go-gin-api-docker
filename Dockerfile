FROM golang:1.22.2-alpine AS builder

WORKDIR /app

# Copy go mod and sum files
COPY ./main.go ./main.go

# Download any dependencies
RUN go mod init example/api

# Add the required dependencies
RUN go mod tidy

# Copy the source from the current directory to the working Directory inside the container
COPY . .

# Build the Go app
RUN go build -o main .

# Start a new stage from scratch
FROM alpine:latest

WORKDIR /root/

# Copy the Pre-built binary file from the previous stage
COPY --from=builder /app/main .

# Expose port 8080 to the outside world
EXPOSE 8080

# Command to run the executable
CMD ["./main"]
