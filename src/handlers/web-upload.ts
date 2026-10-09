import type { Env } from '../types';
import { MetadataStore } from '../storage/metadata';
import { uploadToTelegram } from '../telegram/upload';
import { errorResponse } from '../xml/builder';

function sanitizeFilename(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9.-]/g, '_')
    .replace(/_+/g, '_') // Replace multiple underscores with single
    .replace(/^_|_$/g, ''); // Trim underscores from ends
}

export async function handleWebUpload(request: Request, url: URL, env: Env, webBucket: string): Promise<Response> {
  const method = request.method;
  if (method !== 'POST') {
    return errorResponse(405, 'MethodNotAllowed', 'Only POST is allowed.');
  }

  const contentLength = request.headers.get('content-length');
  const size = contentLength ? parseInt(contentLength, 10) : 0;
  
  // 20MB limit
  if (size > 20 * 1024 * 1024) {
    return Response.json({ error: 'File exceeds 20MB limit' }, { status: 413 });
  }

  // Configured web upload bucket (WEB_UPLOAD_BUCKET); auto-created as public on first use
  const bucketName = webBucket.toLowerCase();
  if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(bucketName)) {
    return Response.json({ error: 'WEB_UPLOAD_BUCKET is not a valid bucket name' }, { status: 500 });
  }
  const store = new MetadataStore(env);
  let bucket = await store.getBucket(bucketName);
  if (!bucket) {
    // Single atomic statement: concurrent first uploads hit ON CONFLICT and simply re-read the row
    await env.DB.prepare(
      "INSERT INTO buckets (name, created_at, tg_chat_id, description, is_public) VALUES (?, ?, ?, 'Web upload', 1) ON CONFLICT(name) DO NOTHING"
    ).bind(bucketName, new Date(Math.floor(Date.now() / 1000) * 1000).toISOString(), env.DEFAULT_CHAT_ID).run();
    bucket = await store.getBucket(bucketName);
    if (!bucket) {
      return Response.json({ error: 'Storage bucket not configured' }, { status: 500 });
    }
  }
  // Never flip an existing private bucket to public
  if (!bucket.is_public) {
    return Response.json({ error: 'Web upload bucket is private; make it public or set WEB_UPLOAD_BUCKET=off' }, { status: 403 });
  }

  let filename = url.searchParams.get('name') || 'file';
  const dotIndex = filename.lastIndexOf('.');
  const namePart = dotIndex !== -1 ? filename.slice(0, dotIndex) : filename;
  const extension = dotIndex !== -1 ? sanitizeFilename(filename.slice(dotIndex + 1)) : '';
  
  const sanitized = sanitizeFilename(namePart) || 'file';
  const now = new Date();
  const dateStr = now.toISOString().split('T')[0].replace(/-/g, ''); // YYYYMMDD
  const shortHash = crypto.randomUUID().substring(0, 4);
  
  const key = extension 
    ? `${dateStr}_${sanitized}_${shortHash}.${extension}`
    : `${dateStr}_${sanitized}_${shortHash}`;

  // Anonymous uploads are served publicly from this origin: never keep a client-declared type that a browser
  // would render as a page or script (HTML, SVG, JS, XML...). Unknown types are stored as a plain download.
  const declaredType = (request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  const contentType = /^(image\/(png|jpeg|gif|webp|avif|bmp|heic|heif)|video\/[a-z0-9.+-]+|audio\/[a-z0-9.+-]+|application\/pdf|text\/plain)$/.test(declaredType)
    ? declaredType
    : 'application/octet-stream';
  
  const body = await request.arrayBuffer();
  if (body.byteLength === 0) {
    return Response.json({ error: 'Empty file' }, { status: 400 });
  }
  // Content-Length may be absent (chunked body): enforce the limit on the bytes actually read
  if (body.byteLength > 20 * 1024 * 1024) {
    return Response.json({ error: 'File exceeds 20MB limit' }, { status: 413 });
  }

  const actualSize = body.byteLength;
  const hashBuffer = await crypto.subtle.digest('MD5', body);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const etag = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  try {
    const uploadResult = await uploadToTelegram(
      body,
      bucket.tg_chat_id,
      key,
      contentType,
      env,
      bucket.tg_topic_id
    );

    await store.putObject({
      bucket: bucketName,
      key,
      size: actualSize,
      contentType,
      etag,
      tgFileId: uploadResult.tgFileId,
      tgFileUniqueId: uploadResult.tgFileUniqueId,
      tgMessageId: uploadResult.tgMessageId,
      tgChatId: uploadResult.tgChatId,
    });

    const publicUrl = `${url.origin}/${bucketName}/${key}`;
    
    return Response.json({ 
      url: publicUrl,
      name: key,
      size: actualSize
    }, { status: 200 });

  } catch (error: any) {
    console.error('Web Upload Error:', error);
    return Response.json({ error: 'Failed to upload file to backend' }, { status: 500 });
  }
}
