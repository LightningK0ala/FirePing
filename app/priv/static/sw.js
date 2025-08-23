// FirePing Service Worker for Web Push Notifications
self.addEventListener("push", function (event) {
  console.log("Push message received:", event);

  const options = {
    body: "You have a new notification from FirePing",
    icon: "/images/notification-icon.svg",
    badge: "/images/notification-badge.svg",
    tag: "fireping-notification",
    requireInteraction: true,
    actions: [
      {
        action: "view",
        title: "View Dashboard",
      },
      {
        action: "dismiss",
        title: "Dismiss",
      },
    ],
  };

  let title = "FirePing Alert";

  if (event.data) {
    try {
      const data = event.data.json();
      console.log("Push notification data:", data);

      title = data.title || title;
      options.body = data.body || options.body;

      // Use server-provided icon and badge if available
      if (data.icon) {
        options.icon = data.icon;
      }
      if (data.badge) {
        options.badge = data.badge;
      }
      if (data.image) {
        options.image = data.image;
      }
      if (data.tag) {
        options.tag = data.tag;
      }
      if (data.requireInteraction !== undefined) {
        options.requireInteraction = data.requireInteraction;
      }
      if (data.actions) {
        options.actions = data.actions;
      }

      if (data.data) {
        options.data = data.data;
      }
    } catch (e) {
      console.error("Error parsing push notification data:", e);
    }
  }

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", function (event) {
  console.log("Notification clicked:", event);

  event.notification.close();

  if (event.action === "view" || !event.action) {
    event.waitUntil(
      clients.matchAll().then(function (clientList) {
        // If there's already a window open, focus it
        for (let client of clientList) {
          if (client.url.includes(self.location.origin) && "focus" in client) {
            return client.focus();
          }
        }

        // Otherwise, open a new window
        if (clients.openWindow) {
          return clients.openWindow("/");
        }
      })
    );
  }
  // 'dismiss' action just closes the notification (already handled above)
});

self.addEventListener("notificationclose", function (event) {
  console.log("Notification closed:", event);
});

// Handle service worker installation
self.addEventListener("install", function (event) {
  console.log("FirePing Service Worker installing...");
  self.skipWaiting();
});

self.addEventListener("activate", function (event) {
  console.log("FirePing Service Worker activated");
  event.waitUntil(clients.claim());
});
