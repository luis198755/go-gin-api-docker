#!/bin/bash

# Create project directory
#mkdir -p go-gin-api-docker
#cd go-gin-api-docker

# Create main.go
cat > main.go << EOL
package main

import (
    "database/sql"
    "fmt"
    "log"
    "net/http"
    "os"
    "strconv"

    "github.com/gin-gonic/gin"
    _ "github.com/go-sql-driver/mysql"
    swaggerFiles "github.com/swaggo/files"
    ginSwagger "github.com/swaggo/gin-swagger"
    _ "example/api/docs" // replace with actual path to your docs package
)

type User struct {
    ID    int    `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}

var db *sql.DB

// @title User API
// @version 1.0
// @description This is a sample User API with Swagger documentation
// @host localhost:8080
// @BasePath /api/v1
func main() {
    dbHost := os.Getenv("DB_HOST")
    dbUser := os.Getenv("DB_USER")
    dbPassword := os.Getenv("DB_PASSWORD")
    dbName := os.Getenv("DB_NAME")

    dbURI := fmt.Sprintf("%s:%s@tcp(%s:3306)/%s?parseTime=true", dbUser, dbPassword, dbHost, dbName)

    var err error
    db, err = sql.Open("mysql", dbURI)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    r := gin.Default()

    v1 := r.Group("/api/v1")
    {
        users := v1.Group("/users")
        {
            users.GET("", getUsers)
            users.GET("/:id", getUser)
            users.POST("", createUser)
            users.PUT("/:id", updateUser)
            users.DELETE("/:id", deleteUser)
        }
    }

    r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

    r.Run(":8080")
}

// @Summary Get all users
// @Description Get a list of all users
// @Produce json
// @Success 200 {array} User
// @Router /users [get]
func getUsers(c *gin.Context) {
    var users []User
    rows, err := db.Query("SELECT id, name, email FROM users")
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    defer rows.Close()

    for rows.Next() {
        var user User
        if err := rows.Scan(&user.ID, &user.Name, &user.Email); err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        users = append(users, user)
    }

    c.JSON(http.StatusOK, users)
}

// @Summary Get a user
// @Description Get a user by ID
// @Produce json
// @Param id path int true "User ID"
// @Success 200 {object} User
// @Router /users/{id} [get]
func getUser(c *gin.Context) {
    id := c.Param("id")
    var user User
    err := db.QueryRow("SELECT id, name, email FROM users WHERE id = ?", id).Scan(&user.ID, &user.Name, &user.Email)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
        return
    }
    c.JSON(http.StatusOK, user)
}

// @Summary Create a user
// @Description Create a new user
// @Accept json
// @Produce json
// @Param user body User true "User object"
// @Success 201 {object} User
// @Router /users [post]
func createUser(c *gin.Context) {
    var user User
    if err := c.ShouldBindJSON(&user); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    result, err := db.Exec("INSERT INTO users (name, email) VALUES (?, ?)", user.Name, user.Email)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    id, _ := result.LastInsertId()
    user.ID = int(id)
    c.JSON(http.StatusCreated, user)
}

// @Summary Update a user
// @Description Update a user by ID
// @Accept json
// @Produce json
// @Param id path int true "User ID"
// @Param user body User true "User object"
// @Success 200 {object} User
// @Router /users/{id} [put]
func updateUser(c *gin.Context) {
    idStr := c.Param("id")
    id, err := strconv.Atoi(idStr)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
        return
    }

    var user User
    if err := c.ShouldBindJSON(&user); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    _, err = db.Exec("UPDATE users SET name = ?, email = ? WHERE id = ?", user.Name, user.Email, id)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    user.ID = id
    c.JSON(http.StatusOK, user)
}

// @Summary Delete a user
// @Description Delete a user by ID
// @Produce json
// @Param id path int true "User ID"
// @Success 204 "No Content"
// @Router /users/{id} [delete]
func deleteUser(c *gin.Context) {
    id := c.Param("id")
    _, err := db.Exec("DELETE FROM users WHERE id = ?", id)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.Status(http.StatusNoContent)
}

EOL

# Create Dockerfile
cat > Dockerfile << EOL
FROM golang:1.22.2-alpine AS builder

WORKDIR /app

# Copy go mod and sum files
COPY ./main.go ./main.go

# Download any dependencies
RUN go mod init example/api

# Add dependencies
RUN go get github.com/swaggo/swag/cmd/swag

# Install swag CLI Tool:
RUN go install github.com/swaggo/swag/cmd/swag@latest

# Add the required dependencies
RUN go mod tidy

# Copy the source from the current directory to the working Directory inside the container
#COPY ./docs ./docs
RUN swag --version 

RUN swag init

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
EOL

# Create docker-compose.yml
cat > docker-compose.yml << EOL
version: '3.8'

services:
  api:
    build: .
    ports:
      - "8080:8080"
    depends_on:
      - db
    environment:
      - DB_HOST=db
      - DB_USER=root
      - DB_PASSWORD=rootpassword
      - DB_NAME=userdb

  db:
    image: mariadb:10.5
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: userdb
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

volumes:
  mariadb_data:
EOL

# Create init.sql
cat > init.sql << EOL
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL
);

INSERT INTO users (name, email) VALUES 
  ('John Doe', 'john@example.com'),
  ('Jane Smith', 'jane@example.com');
EOL

# Initialize Go module
go mod init example/api

# Add dependencies
go get github.com/gin-gonic/gin
go get github.com/go-sql-driver/mysql
go get github.com/swaggo/swag/cmd/swag
go get github.com/swaggo/gin-swagger
go get github.com/swaggo/files

# Ensure all dependencies are properly recorded
go mod tidy

# Generate Swagger documentation
go install github.com/swaggo/swag/cmd/swag@latest

export PATH=$PATH:$HOME/go/bin

source ~/.zshrc

swag --version 

swag init

echo "Project files have been generated successfully!"
echo "go.mod and go.sum files have been created and updated."
echo "To run the project, use: docker-compose up --build"