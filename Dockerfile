FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY app.js ./

# Expose port
EXPOSE 3000

# Start the application
CMD ["npm", "start"]
