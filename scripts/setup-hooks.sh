#!/bin/bash

# Setup Git hooks for the project
echo "Setting up Git hooks..."

# Create pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh

# Pre-commit hook to check Elixir code formatting
echo "Checking code formatting..."

# Try Docker first (more reliable in this project)
if command -v docker-compose >/dev/null 2>&1; then
    # Ensure services are running
    docker-compose up -d --quiet-pull 2>/dev/null || true
    sleep 2
    
    # Try exec first (faster if container is running), fallback to run
    if docker-compose exec -T app mix format --check-formatted 2>/dev/null; then
        echo "✅ Code formatting is correct!"
        exit 0
    else
        # If exec failed, try run (handles container not running)
        if docker-compose run --rm app mix format --check-formatted 2>/dev/null; then
            echo "✅ Code formatting is correct!"
            exit 0
        else
            echo "❌ Code is not properly formatted!"
            echo "Run 'make format' to fix formatting issues, then commit again."
            exit 1
        fi
    fi
elif command -v mix >/dev/null 2>&1 && [ -d "app" ]; then
    # Fallback to local mix
    cd app && mix format --check-formatted
    if [ $? -ne 0 ]; then
        echo "❌ Code is not properly formatted!"
        echo "Run 'make format' to fix formatting issues, then commit again."
        exit 1
    fi
    echo "✅ Code formatting is correct!"
    exit 0
else
    echo "Warning: Neither mix nor docker-compose found. Skipping format check."
    exit 0
fi
EOF

# Make it executable
chmod +x .git/hooks/pre-commit

echo "Git hooks installed successfully!"
echo "Your code will now be checked for proper formatting before commits."
