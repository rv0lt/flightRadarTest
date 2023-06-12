# Use the official Python image as the base image
FROM python:3.9-slim

# Install flask
RUN pip install --no-cache-dir flask

# Copy the API code into the container
COPY api.py .

# Expose the port on which the API will run
EXPOSE 5000

# Set the command to run the API when the container starts
CMD ["python", "api.py"]
