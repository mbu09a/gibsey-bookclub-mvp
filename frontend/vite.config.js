import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Proxy /api/v1 requests to our FastAPI backend
      '/api/v1': {
        target: 'http://localhost:8000', // Your FastAPI server address
        changeOrigin: true, // Recommended for virtual hosting setups
        // rewrite: (path) => path.replace(/^\/api\/v1/, '/api/v1') // Usually not needed if prefix is same
      }
    }
  }
})
