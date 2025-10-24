### Ubuntu npm Installation Prerequisites
- Ensure that Node.js and npm are installed. You can install them using the following commands:
  ```bash
  sudo apt update
  sudo apt install nodejs npm
  ```

### Steps to Install npm on Ubuntu
1. Open your terminal.
2. Update your package index:
   ```bash
   sudo apt update
   ```
3. Install npm:
   ```bash
   sudo apt install npm
   ```

### Troubleshooting npm Registry Access Issues
- If you face issues accessing the npm registry, try the following solutions:
  1. Check your internet connection.
  2. Ensure that your npm is configured to use the correct registry:
     ```bash
     npm config get registry
     ```
     If it is not set to `https://registry.npmjs.org/`, you can set it using:
     ```bash
     npm config set registry https://registry.npmjs.org/
     ```
  3. If you continue to have issues, try clearing the npm cache:
     ```bash
     npm cache clean --force
     ```
