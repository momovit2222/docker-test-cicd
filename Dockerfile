#
# ----------------- NOTE ----------------- #
# This Dockerfile is a multi-stage build, which is a best practice for creating
# optimized and secure Docker images. It separates the build environment from
# the final runtime environment.
#
# STAGE 1: "builder"
#   - Uses a full Node.js image with build tools.
#   - Installs all dependencies, including 'devDependencies'.
#   - Copies source code.
#   - (Optional) Runs a build script (e.g., for TypeScript, React, etc.).
#
# STAGE 2: "production"
#   - Starts from a fresh, clean Node.js image.
#   - Sets up a non-root user for security.
#   - Copies only the necessary artifacts (package.json, production node_modules,
#     and source code) from the "builder" stage.
#   - This results in a smaller, more secure final image without build tools,
#     source maps, or development dependencies.
#
# ---------------------------------------- #


# ----------------- STAGE 1: Build ----------------- #
# Use a specific version of the Node.js Alpine image. Pinning versions is crucial
# for reproducible builds. Alpine is used for its small size.
# We name this stage "builder" to reference it later.
FROM node:18.19.1-alpine3.19 AS builder

# Set the working directory in the container.
WORKDIR /app

# --- .dockerignore hint ---
# It's a critical best practice to use a .dockerignore file to prevent
# copying unnecessary or sensitive files into the build context and image.
# An example .dockerignore for a Node.js project:
#
# node_modules
# .npm
# .git
# .env
# Dockerfile
# *.md
#
# --------------------------

# Copy package.json and package-lock.json first. This leverages Docker's layer
# caching. The 'npm ci' step will only be re-run if these files change.
COPY package*.json ./

# Use 'npm ci' (clean install) instead of 'npm install'. It's faster, more
# reliable for CI/CD environments, and strictly uses the package-lock.json.
# This installs all dependencies, including devDependencies, needed for building.
RUN npm ci

# Copy the rest of the application source code into the image.
COPY . .

# (Optional) If your project has a build step (e.g., for TypeScript, React, Vue),
# uncomment the following line.
# RUN npm run build


# ----------------- STAGE 2: Production ----------------- #
# Start a new, clean stage from the same base image for the final production image.
FROM node:18.19.1-alpine3.19

# Add OCI (Open Container Initiative) labels for better image metadata.
# These labels help with organizing and automating container infrastructure.
LABEL org.opencontainers.image.authors="your-name-or-team@example.com"
LABEL org.opencontainers.image.description="Production image for the Node.js application."
LABEL org.opencontainers.image.source="https://github.com/your-repo/your-project"
LABEL org.opencontainers.image.title="my-node-app"
LABEL org.opencontainers.image.vendor="Your Company"
LABEL org.opencontainers.image.version="1.0.0"

# Set the environment to "production". This is a standard convention that many
# libraries (like Express) use to enable performance and security optimizations.
ENV NODE_ENV=production

# Create a dedicated, non-root user and group for running the application.
# Running as a non-root user is a critical security best practice.
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs

# Set the working directory.
WORKDIR /app

# Copy package files from the 'builder' stage.
COPY --from=builder /app/package*.json ./

# Install *only* production dependencies and clean the npm cache to reduce
# the final image size.
RUN npm ci --omit=dev && npm cache clean --force

# Copy the application source code (and build output if any) from the 'builder' stage.
# We also set the ownership of all files to the non-root user.
# The --chown flag is an efficient way to set permissions during the COPY operation.
COPY --from=builder --chown=nodejs:nodejs /app .

# Switch to the non-root user. Any subsequent commands (like CMD) will be
# executed as this user.
USER nodejs

# Expose the port the application will run on. This is documentation for the user
# and allows for easier port mapping.
EXPOSE 3000

# Add a HEALTHCHECK. This allows Docker or an orchestrator (like Kubernetes) to
# check if the application is still running and healthy.
# This example curls localhost; you should replace the command with a check
# that is appropriate for your application (e.g., hitting a /healthz endpoint).
# The 'wget' command is used here as 'curl' is not included in Alpine by default.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/ || exit 1

# The command to run the application.
# Using the exec form `["node", "server.js"]` is often preferred over `["npm", "start"]`
# to reduce overhead and ensure signals are handled correctly by the Node process (PID 1).
# However, `npm start` is idiomatic and works well for simple cases.
CMD [ "npm", "start" ]