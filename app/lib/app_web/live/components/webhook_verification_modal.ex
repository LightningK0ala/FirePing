defmodule AppWeb.Components.WebhookVerificationModal do
  use AppWeb, :live_component

  alias App.Webhook

  def handle_event("close_webhook_modal", _params, socket) do
    send(self(), :close_webhook_modal)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white dark:bg-zinc-900 rounded-lg shadow-xl max-w-4xl w-full mx-4 max-h-[90vh] overflow-y-auto">
        <div class="p-6">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-semibold text-zinc-900 dark:text-zinc-100">
              Webhook Signature Verification
            </h2>
            <button
              phx-click="close_webhook_modal"
              phx-target={@myself}
              class="p-2 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded transition-colors"
            >
              ✕
            </button>
          </div>

          <div class="space-y-6">
            <!-- Public Key Section -->
            <div>
              <h3 class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-3">
                Public Key for Verification
              </h3>
              <div class="bg-zinc-50 dark:bg-zinc-800 rounded-lg p-4">
                <p class="text-sm text-zinc-600 dark:text-zinc-400 mb-2">
                  Use this public key to verify webhook signatures:
                </p>
                <div class="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded p-3">
                  <code class="text-xs text-zinc-800 dark:text-zinc-200 break-all">
                    <%= case Webhook.get_webhook_public_key_b64() do %>
                      <% nil -> %>
                        No public key configured. Please set WEBHOOK_PUBLIC_KEY in your environment.
                      <% key -> %>
                        {key}
                    <% end %>
                  </code>
                </div>
              </div>
            </div>
            
    <!-- Security Notice -->
            <div class="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700 rounded-lg p-4 mb-6">
              <div class="flex items-start gap-3">
                <div class="text-amber-600 dark:text-amber-400 text-xl">🔒</div>
                <div>
                  <h3 class="font-medium text-amber-900 dark:text-amber-100 mb-1">Security Notice</h3>
                  <p class="text-sm text-amber-700 dark:text-amber-200">
                    All webhook payloads include cryptographic signatures that should be verified to ensure authenticity and prevent tampering.
                    Always validate the signature before processing webhook data in production systems.
                  </p>
                </div>
              </div>
            </div>
            
    <!-- Webhook Payload Format -->
            <div>
              <h3 class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-3">
                Webhook Payload Format
              </h3>
              <div class="bg-zinc-50 dark:bg-zinc-800 rounded-lg p-4">
                <p class="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
                  Here's an example of what your webhook endpoint will receive:
                </p>
                <div class="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded p-3">
                  <pre class="text-xs text-zinc-800 dark:text-zinc-200 overflow-x-auto"><code><%= raw(~s|
                    {
                      "body": "2 new fires detected (4 total) near 'Home' (1 of 2 active incidents)",
                      "data": {
                        "fire_count": 2,
                        "location_id": "a7d9bf7b-9fd2-4a79-8753-5359cd130eed",
                        "incident_id": "1ac55c10-f54b-4059-849c-05100120d47d",
                        "incident_short_id": "1ac5",
                        "total_fire_count": 4,
                        "active_incidents_count": 2,
                        "incident_type": "ongoing",
                        "location_name": "Home",
                        "has_new_incidents": false
                      },
                      "notification_id": "3aaa79e9-8346-4ef1-aff9-175bf70bd584",
                      "sent_at": "2025-08-26T05:20:11.774985Z",
                      "signature": "Ew85apFtdUA9puULhXXrFZL55Pldyxde3OTp/1rY3Zxhvv3+aDy/Yxd+kD3GJ/0nS+/vd8PIfKumVCQ93f6MAw==",
                      "signature_timestamp": "1756185611",
                      "title": "Fire incident updated (ID: 1ac5)",
                      "type": "fire_alert"
                    }
                    |) %></code></pre>
                </div>
              </div>
            </div>
            
    <!-- Verification Instructions -->
            <div>
              <h3 class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-3">
                How to Verify Signatures
              </h3>
              <div class="bg-zinc-50 dark:bg-zinc-800 rounded-lg p-4">
                <p class="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
                  To verify that a webhook came from FirePing, verify the signature using Ed25519:
                </p>
                
    <!-- JavaScript Example -->
                <div class="mb-4">
                  <h4 class="text-md font-medium text-zinc-900 dark:text-zinc-100 mb-2">
                    JavaScript Example
                  </h4>
                  <div class="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded p-3">
                    <pre class="text-xs text-zinc-800 dark:text-zinc-200 overflow-x-auto"><code><%= raw(~s|
                      // Using the Web Crypto API
                      async function verifyWebhookSignature(payload, signature, timestamp, publicKey) {
                        // Remove signature fields from payload for verification
                        const { signature: _, signature_timestamp: __, ...payloadToVerify } = payload;

                        // Create the string that was signed
                        const stringToVerify = JSON.stringify(payloadToVerify) + timestamp;

                        // Import the public key
                        const keyData = Uint8Array.from(atob(publicKey), c => c.charCodeAt(0));
                        const key = await crypto.subtle.importKey(
                          'spki',
                          keyData,
                          { name: 'Ed25519' },
                          false,
                          ['verify']
                        );

                        // Verify the signature
                        const signatureData = Uint8Array.from(atob(signature), c => c.charCodeAt(0));
                        const stringData = new TextEncoder().encode(stringToVerify);

                        return await crypto.subtle.verify('Ed25519', key, signatureData, stringData);
                      }

                      // Usage
                      const isValid = await verifyWebhookSignature(
                        webhookPayload,
                        webhookPayload.signature,
                        webhookPayload.signature_timestamp,
                        'YOUR_PUBLIC_KEY_HERE'
                      );
                      |) %></code></pre>
                  </div>
                </div>
                
    <!-- Python Example -->
                <div class="mb-4">
                  <h4 class="text-md font-medium text-zinc-900 dark:text-zinc-100 mb-2">
                    Python Example
                  </h4>
                  <div class="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded p-3">
                    <pre class="text-xs text-zinc-800 dark:text-zinc-200 overflow-x-auto"><code><%= raw(~s|
                      import base64
                      import json
                      from cryptography.hazmat.primitives import serialization
                      from cryptography.hazmat.primitives.asymmetric import ed25519

                      def verify_webhook_signature(payload, signature, timestamp, public_key_b64):
                          # Remove signature fields from payload for verification
                          payload_to_verify = {k: v for k, v in payload.items()
                                              if k not in ['signature', 'signature_timestamp']}

                          # Create the string that was signed
                          string_to_verify = json.dumps(payload_to_verify) + timestamp

                          # Import the public key
                          public_key_data = base64.b64decode(public_key_b64)
                          public_key = ed25519.Ed25519PublicKey.from_public_bytes(public_key_data)

                          # Verify the signature
                          signature_data = base64.b64decode(signature)
                          string_data = string_to_verify.encode('utf-8')

                          try:
                              public_key.verify(signature_data, string_data)
                              return True
                          except:
                              return False

                      # Usage
                      is_valid = verify_webhook_signature(
                          webhook_payload,
                          webhook_payload['signature'],
                          webhook_payload['signature_timestamp'],
                          'YOUR_PUBLIC_KEY_HERE'
                      )
                      |) %></code></pre>
                  </div>
                </div>
                
    <!-- Node.js Example -->
                <div>
                  <h4 class="text-md font-medium text-zinc-900 dark:text-zinc-100 mb-2">
                    Node.js Example
                  </h4>
                  <div class="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded p-3">
                    <pre class="text-xs text-zinc-800 dark:text-zinc-200 overflow-x-auto"><code><%= raw(~s|
                      const crypto = require('crypto');

                      function verifyWebhookSignature(payload, signature, timestamp, publicKey) {
                        // Remove signature fields from payload for verification
                        const { signature: _, signature_timestamp: __, ...payloadToVerify } = payload;

                        // Create the string that was signed
                        const stringToVerify = JSON.stringify(payloadToVerify) + timestamp;

                        // Verify the signature
                        const signatureData = Buffer.from(signature, 'base64');
                        const stringData = Buffer.from(stringToVerify, 'utf8');
                        const publicKeyData = Buffer.from(publicKey, 'base64');

                        try {
                          const verifier = crypto.createVerify('RSA-SHA256');
                          verifier.update(stringData);
                          return verifier.verify(publicKeyData, signatureData);
                        } catch (error) {
                          return false;
                        }
                      }

                      // Usage
                      const isValid = verifyWebhookSignature(
                        webhookPayload,
                        webhookPayload.signature,
                        webhookPayload.signature_timestamp,
                        'YOUR_PUBLIC_KEY_HERE'
                      );
                      |) %></code></pre>
                  </div>
                </div>
              </div>
            </div>
            
    <!-- Security Notes -->
            <div>
              <h3 class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-3">
                Security Notes
              </h3>
              <div class="bg-amber-50 dark:bg-amber-950/50 border border-amber-200 dark:border-amber-800 rounded-lg p-4">
                <ul class="text-sm text-amber-800 dark:text-amber-200 space-y-2">
                  <li>• Always verify the signature before processing webhook data</li>
                  <li>• Check that the timestamp is recent (within 1 hour)</li>
                  <li>• Use HTTPS endpoints to receive webhooks</li>
                  <li>• Keep your webhook URL private and secure</li>
                  <li>• Implement rate limiting on your webhook endpoint</li>
                </ul>
              </div>
            </div>
          </div>

          <div class="mt-6 flex justify-end">
            <button
              phx-click="close_webhook_modal"
              phx-target={@myself}
              class="px-4 py-2 bg-zinc-600 text-white text-sm font-medium rounded-md hover:bg-zinc-700 transition-colors"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
