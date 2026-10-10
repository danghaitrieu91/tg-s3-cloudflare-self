export function renderWebUI(origin: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Upload File | TG-S3</title>
  <style>
    :root {
      --primary: #c21a1a;
      --primary-hover: #a11414;
      --bg: #f8fafc;
      --card-bg: #ffffff;
      --text: #1e293b;
      --text-light: #64748b;
      --border: #e2e8f0;
      --border-hover: #cbd5e1;
      --success: #10b981;
      --error: #ef4444;
      --radius: 12px;
      --shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.5;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    .container {
      max-width: 800px;
      margin: 0 auto;
      padding: 40px 20px;
      width: 100%;
    }

    .header {
      text-align: center;
      margin-bottom: 40px;
    }

    .header h1 {
      font-size: 2rem;
      font-weight: 700;
      color: var(--primary);
      margin-bottom: 8px;
    }

    .header p {
      color: var(--text-light);
      font-size: 1.1rem;
    }

    .upload-area {
      background: var(--card-bg);
      border: 2px dashed var(--border);
      border-radius: var(--radius);
      padding: 60px 20px;
      text-align: center;
      transition: all 0.2s ease;
      cursor: pointer;
      box-shadow: var(--shadow);
      margin-bottom: 40px;
      position: relative;
      overflow: hidden;
    }

    .upload-area:hover, .upload-area.drag-active {
      border-color: var(--primary);
      background: #fef2f2;
    }

    .upload-icon {
      width: 64px;
      height: 64px;
      margin: 0 auto 16px;
      color: var(--primary);
      opacity: 0.8;
    }

    .upload-title {
      font-size: 1.25rem;
      font-weight: 600;
      margin-bottom: 8px;
    }

    .upload-subtitle {
      color: var(--text-light);
      font-size: 0.95rem;
    }

    #file-input {
      display: none;
    }

    /* Progress Overlay */
    .progress-overlay {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(255, 255, 255, 0.95);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.2s;
    }

    .upload-area.uploading .progress-overlay {
      opacity: 1;
      pointer-events: all;
    }

    .spinner {
      width: 40px;
      height: 40px;
      border: 4px solid var(--border);
      border-top-color: var(--primary);
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin-bottom: 16px;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    .progress-text {
      font-weight: 600;
      color: var(--primary);
    }

    /* File List */
    .file-list-container {
      background: var(--card-bg);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      overflow: hidden;
      display: none; /* Hidden initially */
    }

    .file-list-header {
      padding: 20px;
      border-bottom: 1px solid var(--border);
      font-weight: 600;
      font-size: 1.1rem;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .clear-btn {
      background: none;
      border: none;
      color: var(--error);
      cursor: pointer;
      font-size: 0.9rem;
      font-weight: 500;
    }
    .clear-btn:hover { text-decoration: underline; }

    .file-list {
      list-style: none;
      max-height: 400px;
      overflow-y: auto;
    }

    .file-item {
      display: flex;
      align-items: center;
      padding: 16px 20px;
      border-bottom: 1px solid var(--border);
      gap: 16px;
    }

    .file-item:last-child {
      border-bottom: none;
    }

    .file-preview {
      width: 48px;
      height: 48px;
      border-radius: 8px;
      background: var(--bg);
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
      flex-shrink: 0;
      border: 1px solid var(--border);
    }

    .file-preview img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }

    .file-preview svg {
      width: 24px;
      height: 24px;
      color: var(--text-light);
    }

    .file-info {
      flex: 1;
      min-width: 0;
    }

    .file-name {
      font-weight: 500;
      margin-bottom: 4px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .file-meta {
      font-size: 0.85rem;
      color: var(--text-light);
    }

    .file-actions {
      display: flex;
      gap: 8px;
    }

    .btn {
      padding: 8px 16px;
      border-radius: 6px;
      font-size: 0.9rem;
      font-weight: 500;
      cursor: pointer;
      border: 1px solid transparent;
      transition: all 0.2s;
      text-decoration: none;
    }

    .btn-copy {
      background: var(--primary);
      color: white;
    }

    .btn-copy:hover {
      background: var(--primary-hover);
    }
    
    .btn-copy.copied {
      background: var(--success);
    }

    .btn-open {
      background: white;
      color: var(--text);
      border-color: var(--border);
    }

    .btn-open:hover {
      background: var(--bg);
      border-color: var(--border-hover);
    }

    /* Toast */
    .toast {
      position: fixed;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%) translateY(100px);
      background: var(--text);
      color: white;
      padding: 12px 24px;
      border-radius: 30px;
      font-size: 0.95rem;
      opacity: 0;
      transition: all 0.3s cubic-bezier(0.68, -0.55, 0.265, 1.55);
      z-index: 1000;
      pointer-events: none;
    }

    .toast.show {
      transform: translateX(-50%) translateY(0);
      opacity: 1;
    }
    
    .toast.error {
      background: var(--error);
    }
  </style>
</head>
<body>

  <div class="container">
    <div class="header">
      <h1>TG-S3 Upload</h1>
      <p>Drag and drop to share files instantly (max 20MB)</p>
    </div>

    <div class="upload-area" id="upload-area">
      <input type="file" id="file-input" multiple>
      <svg class="upload-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
      </svg>
      <div class="upload-title">Drag & drop files here</div>
      <div class="upload-subtitle">or click to choose files</div>

      <div class="progress-overlay" id="progress-overlay">
        <div class="spinner"></div>
        <div class="progress-text" id="progress-text">Uploading...</div>
      </div>
    </div>

    <div class="file-list-container" id="file-list-container">
      <div class="file-list-header">
        <span>Uploaded files</span>
        <button class="clear-btn" id="clear-history-btn">Clear history</button>
      </div>
      <ul class="file-list" id="file-list">
        <!-- Rendered via JS -->
      </ul>
    </div>
  </div>

  <div class="toast" id="toast">Link copied!</div>

  <script>
    const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB
    const ORIGIN = "${origin}";

    const uploadArea = document.getElementById('upload-area');
    const fileInput = document.getElementById('file-input');
    const fileListContainer = document.getElementById('file-list-container');
    const fileListEl = document.getElementById('file-list');
    const toast = document.getElementById('toast');
    const progressText = document.getElementById('progress-text');
    const clearHistoryBtn = document.getElementById('clear-history-btn');

    // State
    let uploads = JSON.parse(localStorage.getItem('tgs3_uploads') || '[]');

    // Init
    renderFileList();

    // Event Listeners
    uploadArea.addEventListener('click', () => fileInput.click());
    
    fileInput.addEventListener('change', (e) => {
      handleFiles(e.target.files);
      fileInput.value = ''; // Reset
    });

    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      uploadArea.addEventListener(eventName, preventDefaults, false);
    });

    function preventDefaults(e) {
      e.preventDefault();
      e.stopPropagation();
    }

    ['dragenter', 'dragover'].forEach(eventName => {
      uploadArea.addEventListener(eventName, () => uploadArea.classList.add('drag-active'), false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
      uploadArea.addEventListener(eventName, () => uploadArea.classList.remove('drag-active'), false);
    });

    uploadArea.addEventListener('drop', (e) => {
      handleFiles(e.dataTransfer.files);
    });
    
    clearHistoryBtn.addEventListener('click', () => {
      uploads = [];
      saveUploads();
      renderFileList();
    });

    function showToast(message, isError = false) {
      toast.textContent = message;
      toast.className = \`toast \${isError ? 'error' : ''} show\`;
      setTimeout(() => toast.classList.remove('show'), 3000);
    }

    async function handleFiles(files) {
      if (!files || files.length === 0) return;

      const fileList = Array.from(files);
      
      // Filter out files > 20MB
      const validFiles = fileList.filter(file => {
        if (file.size > MAX_FILE_SIZE) {
          showToast(\`File \${file.name} exceeds 20MB\`, true);
          return false;
        }
        return true;
      });

      if (validFiles.length === 0) return;

      uploadArea.classList.add('uploading');

      for (let i = 0; i < validFiles.length; i++) {
        const file = validFiles[i];
        if (validFiles.length > 1) {
          progressText.textContent = \`Uploading (\${i + 1}/\${validFiles.length}): \${file.name}\`;
        } else {
          progressText.textContent = 'Uploading...';
        }
        await uploadFile(file);
      }

      uploadArea.classList.remove('uploading');
    }

    async function uploadFile(file) {
      try {
        let response;
        // Server rate limit (429): wait Retry-After and resend the same file, up to 3 times
        for (let attempt = 0; ; attempt++) {
          response = await fetch(\`/api/web-upload?name=\${encodeURIComponent(file.name)}\`, {
            method: 'POST',
            headers: {
              'Content-Type': file.type || 'application/octet-stream',
            },
            body: file
          });
          if (response.status !== 429 || attempt >= 3) break;
          const wait = parseInt(response.headers.get('Retry-After') || '60', 10) || 60;
          const prevText = progressText.textContent;
          progressText.textContent = 'Rate limited, waiting ' + wait + 's before retrying ' + file.name + '...';
          await new Promise(r => setTimeout(r, wait * 1000));
          progressText.textContent = prevText;
        }

        if (!response.ok) {
          const err = await response.json().catch(() => ({}));
          throw new Error(err.error || response.statusText);
        }

        const data = await response.json();
        
        // Add to history
        uploads.unshift({
          id: data.name,
          name: file.name,
          url: data.url,
          type: file.type,
          size: file.size,
          date: new Date().toISOString()
        });

        // Keep last 50
        if (uploads.length > 50) uploads = uploads.slice(0, 50);

        saveUploads();
        renderFileList();
        
      } catch (error) {
        showToast(\`Error: \${error.message}\`, true);
        console.error('Upload error:', error);
      }
    }

    function saveUploads() {
      localStorage.setItem('tgs3_uploads', JSON.stringify(uploads));
    }

    function formatBytes(bytes, decimals = 2) {
      if (!+bytes) return '0 Bytes';
      const k = 1024;
      const dm = decimals < 0 ? 0 : decimals;
      const sizes = ['Bytes', 'KB', 'MB', 'GB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return \`\${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} \${sizes[i]}\`;
    }

    function isImage(type) {
      return type && type.startsWith('image/');
    }

    function renderFileList() {
      if (uploads.length === 0) {
        fileListContainer.style.display = 'none';
        return;
      }

      fileListContainer.style.display = 'block';
      fileListEl.innerHTML = '';

      uploads.forEach((file, idx) => {
        const li = document.createElement('li');
        li.className = 'file-item';
        
        // Preview
        const preview = document.createElement('div');
        preview.className = 'file-preview';
        if (isImage(file.type)) {
          preview.innerHTML = \`<img src="\${file.url}" alt="preview" loading="lazy">\`;
        } else {
          preview.innerHTML = \`<svg fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>\`;
        }
        
        // Info
        const info = document.createElement('div');
        info.className = 'file-info';
        
        const nameDate = new Date(file.date).toLocaleDateString(undefined, {
          hour: '2-digit', minute:'2-digit'
        });
        
        info.innerHTML = \`
          <div class="file-name" title="\${file.id}">\${file.id}</div>
          <div class="file-meta">\${formatBytes(file.size)} • \${nameDate}</div>
        \`;
        
        // Actions
        const actions = document.createElement('div');
        actions.className = 'file-actions';
        
        const copyBtn = document.createElement('button');
        copyBtn.className = 'btn btn-copy';
        copyBtn.textContent = 'Copy Link';
        copyBtn.onclick = () => {
          navigator.clipboard.writeText(file.url).then(() => {
            copyBtn.textContent = 'Copied!';
            copyBtn.classList.add('copied');
            showToast('Link copied to clipboard');
            setTimeout(() => {
              copyBtn.textContent = 'Copy Link';
              copyBtn.classList.remove('copied');
            }, 2000);
          });
        };
        
        const openBtn = document.createElement('a');
        openBtn.className = 'btn btn-open';
        openBtn.textContent = 'Open';
        openBtn.href = file.url;
        openBtn.target = '_blank';
        openBtn.rel = 'noopener noreferrer';
        
        actions.appendChild(copyBtn);
        actions.appendChild(openBtn);
        
        li.appendChild(preview);
        li.appendChild(info);
        li.appendChild(actions);
        
        fileListEl.appendChild(li);
      });
    }
  </script>
</body>
</html>`;
}
