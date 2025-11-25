#
# ------------------ .dockerignore HINT ------------------ #
# It's crucial to have a .dockerignore file in the same directory as your Dockerfile
# to prevent copying unnecessary or sensitive files into your image. This speeds up
# builds and improves security.
#
# Example .dockerignore:
#
# node_modules
# npm-debug.log
# .git
# .gitignore
# .env
# Dockerfile
# README.md
#
# -------------------------------------------------------- #

# Use a specific version of Node.js for reproducibility.
# Using 'ARG' allows these to be easily updated or overridden at build time.
ARG NODE_VERSION=18.19.1
# Using the 'slim' variant as a base for the final image reduces its size.
# The builder stage uses the full 'bullseye' image to ensure build tools are available.
ARG NODE_IMAGE=node

# ======================================================================================
# BUILDER STAGE
# This stage installs all dependencies (including devDependencies), transpiles code
# (if necessary), and prepares the application for the production stage.
# ======================================================================================
FROM ${NODE_IMAGE}:${NODE_VERSION}-bullseye AS builder

# Set the working directory in the container.
WORKDIR /app

# Copy package.json and package-lock.json first to leverage Docker's layer caching.
# This layer is only rebuilt if these files change.
COPY package.json package-lock.json ./

# Install all dependencies, including devDependencies needed for the build process.
# 'npm ci' is used for deterministic, fast, and secure installs based on package-lock.json.
RUN npm ci

# Copy the rest of the application's source code.
COPY . .

# Run the build script if it exists (e.g., for TypeScript, React, Vue, etc.).
# If your application doesn't have a build step, you can safely remove this line.
RUN npm run build

# Remove development dependencies to prepare for the production stage.
# This leaves only the packages required to run the application.
RUN npm prune --production

# ======================================================================================
# FINAL STAGE
# This stage creates the final, lean, and secure production image. It copies only
# the necessary artifacts from the builder stage.
# ======================================================================================
FROM ${NODE_IMAGE}:${NODE_VERSION}-slim AS final

# Set the environment to 'production'. This can enable performance optimizations
# in libraries like Express.js and disables debugging features.
ENV NODE_ENV=production

# Create a dedicated, non-root user and group for the application.
# Running as a non-root user is a critical security best practice.
# The user and group IDs (1001) are chosen to be consistent and avoid conflicts.
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs

# Set the working directory.
WORKDIR /app

# Copy the pruned node_modules, package.json, and built application from the builder stage.
# The --chown flag sets the ownership of the copied files to the non-root user.
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./package.json
# If you have a build step, your output is likely in a 'dist' folder.
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
# If you do NOT have a build step, copy your source code instead (e.g., a 'src' folder).
# COPY --from=builder --chown=nodejs:nodejs /app/src ./src

# Switch to the non-root user. Subsequent commands will run as this user.
USER nodejs

# Add OCI (Open Container Initiative) labels for metadata.
# This helps with image organization and automation.
LABEL org.opencontainers.image.source="https://your-repo-url-here.com"
LABEL org.opencontainers.image.description="Production image for the Node.js application"
LABEL org.opencontainers.image.licenses="MIT"

# Expose the port the application will run on.
# This is documentation for the user and a hint for tools.
EXPOSE 3000

# Add a healthcheck to ensure the container is running properly.
# Docker and orchestrators like Kubernetes use this to determine the container's health.
# Adjust the endpoint '/healthz' to your application's actual health check endpoint.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD [ "curl", "-f", "http://localhost:3000/healthz" ] || exit 1

# Define the command to run the application.
# Using 'node' directly (instead of 'npm start') makes the Node.js process PID 1,
# which helps it receive signals like SIGTERM correctly for graceful shutdowns.
# Ensure the path points to your application's entrypoint file.
CMD [ "node", "dist/index.js" ]
# If you don't have a build step, your command might look like this:
# CMD [ "node", "src/index.js" ]