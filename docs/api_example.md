# API Authorization Flow Example

This document demonstrates how to use the `/api/authorize` endpoint to programmatically replicate the user flow of clicking a link.

## Overview

The `/api/authorize` endpoint allows programs to:
1. Request authorization from users via a popup window
2. Get a scoped popup URL for the user to visit
3. Poll for completion status
4. Receive the user's identity information once authorization completes

## API Endpoints

### 1. Create Authorization Request

**POST** `/api/authorize`

Headers:
- `Authorization: Bearer {your_program_api_key}`
- `Content-Type: application/json`

Response:
```json
{
  "auth_id": "8eaa8b02-1018-4075-aec0-7872e5db18aa",
  "popup_url": "http://localhost/popup/authorize/8eaa8b02-1018-4075-aec0-7872e5db18aa",
  "status": "pending",
  "expires_at": "2025-08-27T00:26:18.573Z"
}
```

### 2. Check Authorization Status

**GET** `/api/authorize/{auth_id}/status`

Headers:
- `Authorization: Bearer {your_program_api_key}`

Response (pending):
```json
{
  "auth_id": "8eaa8b02-1018-4075-aec0-7872e5db18aa",
  "status": "pending",
  "created_at": "2025-08-27T00:11:18.546Z"
}
```

Response (completed):
```json
{
  "auth_id": "8eaa8b02-1018-4075-aec0-7872e5db18aa",
  "status": "completed",
  "created_at": "2025-08-27T00:11:18.546Z",
  "idv_rec": "user123",
  "completed_at": "2025-08-27T00:15:30.123Z"
}
```

## Example JavaScript Implementation

```javascript
class SubmitAuthorizer {
  constructor(apiKey, baseUrl = 'http://localhost') {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
  }

  async startAuthorization() {
    const response = await fetch(`${this.baseUrl}/api/authorize`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to create authorization request');
    }

    const data = await response.json();
    return data;
  }

  async checkStatus(authId) {
    const response = await fetch(`${this.baseUrl}/api/authorize/${authId}/status`, {
      headers: {
        'Authorization': `Bearer ${this.apiKey}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to check authorization status');
    }

    return response.json();
  }

  async authorize() {
    // Step 1: Create authorization request
    const { auth_id, popup_url } = await this.startAuthorization();
    
    // Step 2: Open popup window
    const popup = window.open(
      popup_url,
      'authorization',
      'width=500,height=700,scrollbars=yes,resizable=yes'
    );

    // Step 3: Poll for completion
    return new Promise((resolve, reject) => {
      const pollInterval = setInterval(async () => {
        try {
          const status = await this.checkStatus(auth_id);
          
          if (status.status === 'completed') {
            clearInterval(pollInterval);
            popup.close();
            resolve({
              authId: auth_id,
              idvRec: status.idv_rec,
              completedAt: status.completed_at
            });
          } else if (status.status === 'expired' || status.status === 'failed') {
            clearInterval(pollInterval);
            popup.close();
            reject(new Error(`Authorization ${status.status}`));
          }
        } catch (error) {
          clearInterval(pollInterval);
          popup.close();
          reject(error);
        }
      }, 2000); // Poll every 2 seconds

      // Handle popup closed by user
      const checkClosed = setInterval(() => {
        if (popup.closed) {
          clearInterval(checkClosed);
          clearInterval(pollInterval);
          reject(new Error('Authorization cancelled by user'));
        }
      }, 1000);

      // Cleanup after 15 minutes (expires_at)
      setTimeout(() => {
        clearInterval(pollInterval);
        clearInterval(checkClosed);
        popup.close();
        reject(new Error('Authorization timeout'));
      }, 15 * 60 * 1000);
    });
  }
}

// Usage example
const authorizer = new SubmitAuthorizer('pk_your_api_key_here');

document.getElementById('authorize-btn').addEventListener('click', async () => {
  try {
    const result = await authorizer.authorize();
    console.log('Authorization successful:', result);
    // Now you can use result.idvRec for verification
  } catch (error) {
    console.error('Authorization failed:', error);
  }
});
```

## Integration with Verification

After successful authorization, you can use the `idv_rec` to verify user identity:

```javascript
async function verifyUser(idvRec, firstName, lastName, email, program) {
  const response = await fetch(`/api/verify?idv_rec=${idvRec}&first_name=${firstName}&last_name=${lastName}&email=${email}&program=${program}`);
  return response.json();
}
```

## Security Notes

- API keys should be kept secure and not exposed in client-side code
- Authorization requests expire after 15 minutes
- Each authorization can only be completed once
- The popup automatically closes after successful authorization
- All requests are logged for audit purposes

## Error Handling

Common error responses:

- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Authorization request not found or expired
- `403 Forbidden`: Program is inactive
- `410 Gone`: Authorization request already used

Always handle these errors appropriately in your application.