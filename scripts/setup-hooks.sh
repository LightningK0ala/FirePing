#!/bin/bash

# Setup Git hooks for the project
echo "Setting up Git hooks..."

# Create pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh

# Pre-commit hook to format Elixir code
echo "Running mix format..."

# Check if we're in a Docker environment or have mix available locally
if command -v mix >/dev/null 2>&1 && [ -d "app" ]; then
    # Local mix available
    cd app && mix format
elif command -v docker-compose >/dev/null 2>&1; then
    # Use Docker
    docker-compose exec app mix format 2>/dev/null || \
    docker-compose run --rm app mix format
else
    echo "Warning: Neither mix nor docker-compose found. Skipping format."
    exit 0
fi

# Add formatted files to staging
git add app/lib/ app/test/ 2>/dev/null || true

echo "Code formatted successfully!"
exit 0
EOF

# Make it executable
chmod +x .git/hooks/pre-commit

echo "Git hooks installed successfully!"
echo "Your code will now be automatically formatted on commit."