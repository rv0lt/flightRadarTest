# Use the official Python image as the base image
FROM python:3.9-slim

# Install flask
RUN pip install --no-cache-dir flask

# Copy the API code into the container
COPY api.py .

# Expose the port on which the API will run
EXPOSE 5000

# Add a new user with user id 8877
RUN useradd -u 8877 noroot
# Change to non-root privilege
USER noroot

# Set the command to run the API when the container starts
CMD ["python", "api.py"]
