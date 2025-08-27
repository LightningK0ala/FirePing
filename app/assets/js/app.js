// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
// Leaflet and MessagePack will be loaded from CDN

// Auto-dismiss flash messages
let Hooks = {};
// Simple dark-mode toggle: persists in localStorage and toggles `dark` on <html>
function applyTheme(theme) {
  const root = document.documentElement;
  if (theme === "dark") root.classList.add("dark");
  else root.classList.remove("dark");
}

function initTheme() {
  const saved = localStorage.getItem("fireping:theme");
  const theme =
    saved ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light");
  applyTheme(theme);
  return theme;
}

let currentTheme = initTheme();
window.firepingToggleTheme = function () {
  currentTheme = currentTheme === "dark" ? "light" : "dark";
  localStorage.setItem("fireping:theme", currentTheme);
  applyTheme(currentTheme);
};

Hooks.ThemeToggle = {
  mounted() {
    this.el.addEventListener("click", () => {
      currentTheme = currentTheme === "dark" ? "light" : "dark";
      localStorage.setItem("fireping:theme", currentTheme);
      applyTheme(currentTheme);
    });
  },
};

Hooks.RadiusPreview = {
  mounted() {
    const notify = () =>
      window.dispatchEvent(new CustomEvent("fireping:update-draft"));
    this.el.addEventListener("input", notify);
    this.el.addEventListener("change", notify);
  },
};

Hooks.Flash = {
  mounted() {
    const flash = this.el;
    if (flash.dataset.autoDismiss === "true") {
      setTimeout(() => {
        flash.style.transition = "opacity 0.5s ease-out";
        flash.style.opacity = "0";
        setTimeout(() => {
          if (flash.parentNode) {
            flash.parentNode.removeChild(flash);
          }
        }, 500);
      }, 4000); // Auto-dismiss after 4 seconds
    }
  },
};

Hooks.Geolocation = {
  mounted() {
    const useLocationBtn = this.el;

    useLocationBtn.addEventListener("click", function () {
      if (!navigator.geolocation) {
        alert("Geolocation is not supported by this browser.");
        return;
      }

      // Find the appropriate input fields based on the button context
      let latInput, lngInput;

      // Check if this is a modal button
      if (useLocationBtn.id === "modal-use-my-location") {
        latInput = document.getElementById("modal-latitude-input");
        lngInput = document.getElementById("modal-longitude-input");
      } else if (
        useLocationBtn.id &&
        useLocationBtn.id.startsWith("use-my-location-edit-")
      ) {
        // This is an edit form button
        const locationId = useLocationBtn.id.replace(
          "use-my-location-edit-",
          ""
        );
        latInput = document.getElementById(`edit-latitude-input-${locationId}`);
        lngInput = document.getElementById(
          `edit-longitude-input-${locationId}`
        );
      } else {
        // Fallback to original form
        latInput = document.getElementById("latitude-input");
        lngInput = document.getElementById("longitude-input");
      }

      if (!latInput || !lngInput) {
        alert("Could not find location input fields.");
        return;
      }

      // Show loading state
      useLocationBtn.textContent = "🔄 Getting location...";
      useLocationBtn.disabled = true;

      navigator.geolocation.getCurrentPosition(
        function (position) {
          latInput.value = position.coords.latitude.toFixed(6);
          lngInput.value = position.coords.longitude.toFixed(6);

          // Trigger radius preview update
          window.dispatchEvent(new CustomEvent("fireping:update-draft"));

          // Reset button
          useLocationBtn.textContent = "📍 Use My Location";
          useLocationBtn.disabled = false;
        },
        function (error) {
          let message = "Unable to get your location. ";
          switch (error.code) {
            case error.PERMISSION_DENIED:
              message += "Please enable location access.";
              break;
            case error.POSITION_UNAVAILABLE:
              message += "Location information unavailable.";
              break;
            case error.TIMEOUT:
              message += "Location request timed out.";
              break;
            default:
              message += "An unknown error occurred.";
              break;
          }
          alert(message);

          // Reset button
          useLocationBtn.textContent = "📍 Use My Location";
          useLocationBtn.disabled = false;
        },
        {
          enableHighAccuracy: true,
          timeout: 10000,
          maximumAge: 0,
        }
      );
    });
  },
};

Hooks.Map = {
  mounted() {
    // Fix leaflet marker icon paths
    delete L.Icon.Default.prototype._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png",
      iconUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png",
      shadowUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png",
    });

    // Initialize map centered on San Francisco
    this.map = L.map(this.el, {
      scrollWheelZoom: false,
      gestureHandling: true,
    }).setView([37.7749, -122.4194], 8);

    // Define base layers
    const streetMap = L.tileLayer(
      "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
      {
        attribution: "© Esri",
      }
    );

    const satelliteMap = L.tileLayer(
      "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
      {
        attribution: "© Esri",
      }
    );

    // Labels overlay for satellite view (no attribution to avoid duplication)
    const labelsOverlay = L.tileLayer(
      "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
      {
        attribution: "",
      }
    );

    // Add default layer
    streetMap.addTo(this.map);
    this.currentLayer = streetMap;
    this.streetMap = streetMap;
    this.satelliteMap = satelliteMap;
    this.labelsOverlay = labelsOverlay;

    // Custom toggle control
    const LayerToggle = L.Control.extend({
      onAdd: function (map) {
        const div = L.DomUtil.create(
          "div",
          "leaflet-control-layers leaflet-control"
        );
        div.innerHTML = `
          <button class="layer-toggle-btn" style="
            background: white;
            border: 2px solid #ccc;
            border-radius: 4px;
            padding: 5px 10px;
            cursor: pointer;
            font-size: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
          ">📍 Street</button>
        `;

        L.DomEvent.disableClickPropagation(div);

        return div;
      },
    });

    this.layerToggle = new LayerToggle({ position: "topright" });
    this.layerToggle.addTo(this.map);

    // Add NASA FIRMS attribution
    this.map.attributionControl.addAttribution(
      '<a href="https://firms.modaps.eosdis.nasa.gov/" target="_blank">NASA FIRMS</a>'
    );

    // Toggle functionality
    const toggleBtn = this.map
      .getContainer()
      .querySelector(".layer-toggle-btn");
    toggleBtn.addEventListener("click", () => {
      if (this.currentLayer === this.streetMap) {
        this.map.removeLayer(this.streetMap);
        this.satelliteMap.addTo(this.map);
        this.labelsOverlay.addTo(this.map);
        this.currentLayer = this.satelliteMap;
        toggleBtn.innerHTML = "🛰️ Satellite";
      } else {
        this.map.removeLayer(this.satelliteMap);
        this.map.removeLayer(this.labelsOverlay);
        this.streetMap.addTo(this.map);
        this.currentLayer = this.streetMap;
        toggleBtn.innerHTML = "📍 Street";
      }
    });

    // Handle map data updates from LiveView
    this.handleEvent("update_map_data", (data) => {
      const { locations, fires, fires_msgpack, fires_count } = data;

      let processedFires = fires;

      // If we have MessagePack fires data, decode it
      if (fires_msgpack && window.MessagePack) {
        try {
          // Decode base64 then MessagePack
          const binaryData = Uint8Array.from(atob(fires_msgpack), (c) =>
            c.charCodeAt(0)
          );
          const decodedData = window.MessagePack.decode(binaryData);

          // Convert compact array format back to objects
          processedFires = this.convertCompactFiresToObjects(decodedData);

          console.log(
            `🔥 Decoded ${processedFires.length} fires from MessagePack (${binaryData.length} bytes)`
          );
        } catch (error) {
          console.error("Failed to decode MessagePack fires data:", error);
          // Fallback to regular fires data if available
          processedFires = fires || [];
        }
      } else if (fires_msgpack && !window.MessagePack) {
        console.warn(
          "MessagePack library not loaded, falling back to regular fires data"
        );
        processedFires = fires || [];
      }

      this.updateMapData(locations, processedFires);
    });

    // One-time coordinate picking flow from LiveView
    this.pickOnMapActive = false;
    this.handleEvent("start_pick_on_map", (payload = {}) => {
      try {
        this.pickOnMapActive = true;
        const container = this.map.getContainer();
        if (container) container.style.cursor = "crosshair";

        const onPick = (e) => {
          const { lat, lng } = e.latlng || {};
          this.pickOnMapActive = false;
          if (container) container.style.cursor = "";

          if (typeof lat === "number" && typeof lng === "number") {
            // Show marker feedback
            try {
              if (this.selectionMarker) {
                this.map.removeLayer(this.selectionMarker);
              }
              this.selectionMarker = L.marker([lat, lng], {
                icon: this.getEditingIcon(),
              }).addTo(this.map);
            } catch (_err) {}

            // Send coordinates to LiveView
            const context = payload && payload.context;
            const locationId = payload && payload.location_id;
            if (context === "edit" && locationId) {
              this.pushEvent("map_pick_edit_coords", {
                latitude: Number(lat).toFixed(6),
                longitude: Number(lng).toFixed(6),
                location_id: locationId,
              });
            } else {
              this.pushEvent("map_pick_coords", {
                latitude: Number(lat).toFixed(6),
                longitude: Number(lng).toFixed(6),
              });
            }
          }
        };

        this.map.once("click", onPick);
      } catch (_err) {}
    });

    // Handle map centering from LiveView (for incident and location clicks)
    this.handleEvent("center_map", (data) => {
      const {
        latitude,
        longitude,
        zoom = 14,
        incident_id,
        location_id,
        radius,
        type,
        bounds,
      } = data;

      if (typeof latitude === "number" && typeof longitude === "number") {
        if (bounds && type === "incident") {
          // Use bounds to fit all fires in the incident
          const leafletBounds = L.latLngBounds(
            [bounds.min_lat, bounds.min_lng],
            [bounds.max_lat, bounds.max_lng]
          );
          this.map.fitBounds(leafletBounds, { padding: [20, 20] });
        } else {
          // Fallback to center and zoom
          this.map.setView([latitude, longitude], zoom);
        }
      }
    });

    // Handle form cancellation - clear draft elements
    this.handleEvent("clear_radius_preview", () => {
      this.clearDraftElements();
    });

    // Initialize with empty locations and fire cluster
    this.markersLayer = L.layerGroup().addTo(this.map);
    this.fireCluster = L.markerClusterGroup({
      maxClusterRadius: 50,
      spiderfyOnMaxZoom: true,
      showCoverageOnHover: false,
      zoomToBoundsOnClick: true,
      iconCreateFunction: (cluster) => this.createFireClusterIcon(cluster),
    }).addTo(this.map);

    // Listen for draft update requests (from slider or external triggers)
    window.addEventListener("fireping:update-draft", () =>
      this.updateDraftCircle()
    );

    // Also update draft when form inputs change (create form)
    const latInputEl = document.getElementById("latitude-input");
    const lngInputEl = document.getElementById("longitude-input");
    const radiusInputEl = document.getElementById("radius-input");
    const radiusNumberEl = document.getElementById("radius-number");
    const onChange = () => this.updateDraftCircle();
    if (latInputEl) {
      latInputEl.addEventListener("input", onChange);
      latInputEl.addEventListener("change", onChange);
    }
    if (lngInputEl) {
      lngInputEl.addEventListener("input", onChange);
      lngInputEl.addEventListener("change", onChange);
    }
    const syncRadius = () => {
      if (radiusInputEl && radiusNumberEl) {
        // slider is meters, number is km
        radiusNumberEl.value = String(
          Math.round(Number(radiusInputEl.value || 0) / 1000)
        );
      }
      this.updateDraftCircle();
    };
    if (radiusInputEl) {
      radiusInputEl.addEventListener("input", syncRadius);
      radiusInputEl.addEventListener("change", syncRadius);
    }
    if (radiusNumberEl) {
      radiusNumberEl.addEventListener("input", () => {
        if (radiusInputEl)
          radiusInputEl.value = String(
            Number(radiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
      radiusNumberEl.addEventListener("change", () => {
        if (radiusInputEl)
          radiusInputEl.value = String(
            Number(radiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
    }

    // Also update draft when modal form inputs change
    const modalLatInputEl = document.getElementById("modal-latitude-input");
    const modalLngInputEl = document.getElementById("modal-longitude-input");
    const modalRadiusInputEl = document.getElementById("modal-radius-input");
    const modalRadiusNumberEl = document.getElementById("modal-radius-number");
    const onModalChange = () => this.updateDraftCircle();
    if (modalLatInputEl) {
      modalLatInputEl.addEventListener("input", onModalChange);
      modalLatInputEl.addEventListener("change", onModalChange);
    }
    if (modalLngInputEl) {
      modalLngInputEl.addEventListener("input", onModalChange);
      modalLngInputEl.addEventListener("change", onModalChange);
    }
    const syncModalRadius = () => {
      if (modalRadiusInputEl && modalRadiusNumberEl) {
        // slider is meters, number is km
        modalRadiusNumberEl.value = String(
          Math.round(Number(modalRadiusInputEl.value || 0) / 1000)
        );
      }
      this.updateDraftCircle();
    };
    if (modalRadiusInputEl) {
      modalRadiusInputEl.addEventListener("input", syncModalRadius);
      modalRadiusInputEl.addEventListener("change", syncModalRadius);
    }
    if (modalRadiusNumberEl) {
      modalRadiusNumberEl.addEventListener("input", () => {
        if (modalRadiusInputEl)
          modalRadiusInputEl.value = String(
            Number(modalRadiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
      modalRadiusNumberEl.addEventListener("change", () => {
        if (modalRadiusInputEl)
          modalRadiusInputEl.value = String(
            Number(modalRadiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
    }

    // Attach listeners for edit form when present
    this.currentEditingId = null;
    this.attachEditListeners = () => {
      const eid = this.getEditingId();
      if (!eid || eid === this.currentEditingId) return;
      this.currentEditingId = eid;

      const eLat = document.getElementById(`edit-latitude-input-${eid}`);
      const eLng = document.getElementById(`edit-longitude-input-${eid}`);
      const eRad = document.getElementById(`edit-radius-input-${eid}`);
      const eNum = document.getElementById(`edit-radius-number-${eid}`);
      const onEditChange = () => this.updateDraftCircle();

      if (eLat) {
        eLat.addEventListener("input", onEditChange);
        eLat.addEventListener("change", onEditChange);
      }
      if (eLng) {
        eLng.addEventListener("input", onEditChange);
        eLng.addEventListener("change", onEditChange);
      }
      if (eRad) {
        eRad.addEventListener("input", () => {
          if (eNum)
            eNum.value = String(Math.round(Number(eRad.value || 0) / 1000));
          this.updateDraftCircle();
        });
        eRad.addEventListener("change", () => {
          if (eNum)
            eNum.value = String(Math.round(Number(eRad.value || 0) / 1000));
          this.updateDraftCircle();
        });
      }
      if (eNum) {
        eNum.addEventListener("input", () => {
          if (eRad) eRad.value = String(Number(eNum.value || 0) * 1000);
          this.updateDraftCircle();
        });
        eNum.addEventListener("change", () => {
          if (eRad) eRad.value = String(Number(eNum.value || 0) * 1000);
          this.updateDraftCircle();
        });
      }
    };
    // Try initial attach (if edit mode already active)
    this.attachEditListeners();

    // Allow clicking on the map to populate the add-location form
    this.map.on("click", (e) => {
      // Check for modal form inputs first
      const modalLat = document.getElementById("modal-latitude-input");
      const modalLng = document.getElementById("modal-longitude-input");

      // Check for edit form inputs
      const editingId = this.getEditingId();
      const editLat = editingId
        ? document.getElementById(`edit-latitude-input-${editingId}`)
        : null;
      const editLng = editingId
        ? document.getElementById(`edit-longitude-input-${editingId}`)
        : null;

      // Check for original form inputs (fallback)
      const formLat = document.getElementById("latitude-input");
      const formLng = document.getElementById("longitude-input");

      // Use the first available input set
      const latInput = modalLat || editLat || formLat;
      const lngInput = modalLng || editLng || formLng;

      if (!latInput || !lngInput) return;

      const { lat, lng } = e.latlng;
      latInput.value = Number(lat).toFixed(6);
      lngInput.value = Number(lng).toFixed(6);

      // Show a selection marker for visual feedback
      try {
        if (this.selectionMarker) {
          this.map.removeLayer(this.selectionMarker);
        }
        this.selectionMarker = L.marker([lat, lng], {
          icon: this.getEditingIcon(),
        }).addTo(this.map);
        this.updateDraftCircle();
      } catch (_err) {
        // no-op
      }
    });
  },
  updated() {
    // Invalidate map size when container changes
    setTimeout(() => {
      this.map.invalidateSize();
    }, 100);
    // Re-attach edit listeners if editing id changed
    this.attachEditListeners && this.attachEditListeners();
  },

  convertCompactFiresToObjects(compactData) {
    // Convert compact MessagePack format back to object format
    // Expected format: { format: "compact_v1", fields: ["lat", "lng", "timestamp", "confidence", "frp", "satellite"], data: [[...], [...]] }

    if (
      !compactData ||
      compactData.format !== "compact_v1" ||
      !compactData.data
    ) {
      console.warn("Invalid compact fire data format:", compactData);
      return [];
    }

    const fields = compactData.fields || [
      "lat",
      "lng",
      "timestamp",
      "confidence",
      "frp",
      "satellite",
    ];

    return compactData.data.map((fireArray) => {
      const fireObj = {};
      fields.forEach((field, index) => {
        if (field === "lat") fireObj.latitude = fireArray[index];
        else if (field === "lng") fireObj.longitude = fireArray[index];
        else if (field === "timestamp") {
          // Convert Unix timestamp back to ISO date string
          fireObj.detected_at = new Date(fireArray[index] * 1000).toISOString();
        } else {
          fireObj[field] = fireArray[index];
        }
      });
      return fireObj;
    });
  },

  translateSatelliteName(satelliteCode) {
    switch (satelliteCode) {
      case "N21":
        return "NOAA-21";
      case "N20":
        return "NOAA-20";
      case "NPP":
        return "S-NPP";
      case "N":
        return "S-NPP"; // Suomi NPP satellite
      default:
        return satelliteCode || "Unknown";
    }
  },

  translateConfidence(confidence) {
    switch (String(confidence || "").toLowerCase()) {
      case "h":
        return "High";
      case "n":
        return "Normal";
      case "l":
        return "Low";
      default:
        return "Unknown";
    }
  },

  updateMapData(locations, fires) {
    // Clear existing markers and circles
    this.markersLayer.clearLayers();
    this.fireCluster.clearLayers();

    // Add location markers (blue)
    locations.forEach((location) => {
      const latLng = [location.latitude, location.longitude];

      // Location marker (blue)
      const marker = L.marker(latLng).bindPopup(`
          <strong>📍 ${location.name}</strong><br>
          ${location.latitude.toFixed(4)}, ${location.longitude.toFixed(4)}<br>
          Monitoring radius: ${location.radius}m
        `);

      // Monitoring radius circle
      const circle = L.circle(latLng, {
        radius: location.radius,
        color: "#3b82f6",
        fillColor: "#3b82f6",
        fillOpacity: 0.1,
        weight: 2,
      });

      this.markersLayer.addLayer(marker);
      this.markersLayer.addLayer(circle);
    });

    // Add fire markers to cluster (red/orange)
    fires.forEach((fire) => {
      const lat = Number(fire.latitude);
      const lng = Number(fire.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

      const latLng = [lat, lng];
      const frp = Number(fire.frp) || 0;
      const confidence = fire.confidence || "n";

      const detectedDate = fire.detected_at ? new Date(fire.detected_at) : null;
      const detectedText =
        detectedDate && !isNaN(detectedDate)
          ? detectedDate.toLocaleString()
          : "N/A";

      // Calculate fire age in hours
      const now = new Date();
      const ageHours = detectedDate
        ? (now - detectedDate) / (1000 * 60 * 60)
        : 0;
      const isRecent = ageHours <= 24; // 24 hour cutoff for recent fires

      // Fire marker - color based on age and intensity
      const fireMarker = L.circleMarker(latLng, {
        radius: Math.max(6, Math.min(frp / 4, 14)), // Size based on fire power, bigger for easier clicking
        color: isRecent ? "#dc2626" : "#6b7280", // Red border for recent, gray for old
        fillColor: this.getFireColor(confidence, frp, isRecent),
        fillOpacity: isRecent ? 0.8 : 0.6, // More transparent for older fires
        weight: 1,
      }).bindPopup(`
        <strong>🔥 Fire</strong><br>
        <strong>Detected:</strong> ${detectedText}<br>
        <strong>Age:</strong> ${
          isRecent
            ? `${Math.round(ageHours)}h (recent)`
            : `${Math.round(ageHours)}h (older)`
        }<br>
        <strong>Source:</strong> ${this.translateSatelliteName(
          fire.satellite
        )} satellite - ${this.translateConfidence(
        fire.confidence
      )} confidence<br>
        <strong>Fire Power:</strong> ${frp} MW<br>
        <strong>Coordinates:</strong> ${lat.toFixed(4)}, ${lng.toFixed(4)}
      `);

      // Store fire data on marker for cluster calculations
      fireMarker.fireData = {
        frp: frp,
        confidence: confidence,
        satellite: fire.satellite || "N/A",
        isRecent: isRecent,
        ageHours: ageHours,
      };

      this.fireCluster.addLayer(fireMarker);
    });

    // Set map view based on data
    if (locations.length === 0 && fires.length === 0) {
      // No data - world view
      this.map.setView([20, 0], 2);
    } else if (locations.length === 1 && fires.length === 0) {
      // Single location, no fires - zoom to location + radius
      const location = locations[0];
      const center = [location.latitude, location.longitude];
      const radiusMeters = location.radius + 3000;
      const zoom = this.getZoomForRadius(radiusMeters);
      this.map.setView(center, zoom);
    } else {
      // Multiple items - fit bounds to show all
      const bounds = L.latLngBounds();
      locations.forEach((location) =>
        bounds.extend([location.latitude, location.longitude])
      );
      fires.forEach((fire) => {
        const lat = Number(fire.latitude);
        const lng = Number(fire.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          bounds.extend([lat, lng]);
        }
      });

      if (bounds.isValid()) {
        this.map.fitBounds(bounds, { padding: [50, 50], maxZoom: 14 });
      }
    }

    // Invalidate size after bounds change
    setTimeout(() => {
      this.map.invalidateSize();
    }, 100);
  },

  getEditingIcon() {
    // Simple colored marker using a div icon for draft/edited state
    return L.divIcon({
      className: "draft-marker",
      html: '<div style="width:12px;height:12px;border-radius:9999px;background:#2563eb;box-shadow:0 0 0 3px rgba(37,99,235,0.3)"></div>',
      iconSize: [12, 12],
      iconAnchor: [6, 6],
    });
  },

  updateDraftCircle() {
    // Check for modal form inputs first
    const modalLat = document.getElementById("modal-latitude-input");
    const modalLng = document.getElementById("modal-longitude-input");
    const modalRadius = document.getElementById("modal-radius-input");
    const modalRadiusNumber = document.getElementById("modal-radius-number");

    // Check for edit form inputs
    const eid = this.getEditingId();
    const editLat = eid
      ? document.getElementById(`edit-latitude-input-${eid}`)
      : null;
    const editLng = eid
      ? document.getElementById(`edit-longitude-input-${eid}`)
      : null;
    const editRadius = eid
      ? document.getElementById(`edit-radius-input-${eid}`)
      : null;
    const editRadiusNumber = eid
      ? document.getElementById(`edit-radius-number-${eid}`)
      : null;

    // Check for original form inputs (fallback)
    const formLat = document.getElementById("latitude-input");
    const formLng = document.getElementById("longitude-input");
    const formRadius = document.getElementById("radius-input");
    const formRadiusNumber = document.getElementById("radius-number");
    const formRadiusValue = document.getElementById("radius-value");

    // Use the first available input set
    const latInput = modalLat || editLat || formLat;
    const lngInput = modalLng || editLng || formLng;
    const radiusInput = modalRadius || editRadius || formRadius;
    const radiusNumberEl =
      modalRadiusNumber || editRadiusNumber || formRadiusNumber;
    const radiusValueEl = formRadiusValue; // Only exists in original form

    if (!latInput || !lngInput || !radiusInput) return;

    const lat = Number(latInput.value);
    const lng = Number(lngInput.value);
    const radius = Number(
      radiusInput.value || radiusInput.getAttribute("value") || 0
    );
    if (
      radiusNumberEl &&
      radiusNumberEl.value !== String(Math.round(radius / 1000))
    ) {
      radiusNumberEl.value = String(Math.round(radius / 1000));
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || radius <= 0) return;

    if (radiusValueEl)
      radiusValueEl.textContent = String(Math.round(radius / 1000));

    // Place or update selection marker
    try {
      if (!this.selectionMarker) {
        this.selectionMarker = L.marker([lat, lng], {
          icon: this.getEditingIcon(),
        }).addTo(this.map);
      } else {
        this.selectionMarker.setLatLng([lat, lng]);
      }
    } catch (_err) {}

    // Update draft circle
    try {
      if (this.draftCircle) {
        this.map.removeLayer(this.draftCircle);
      }
      this.draftCircle = L.circle([lat, lng], {
        radius,
        color: "#2563eb",
        fillColor: "#2563eb",
        fillOpacity: 0.08,
        weight: 2,
        dashArray: "4 4",
      }).addTo(this.map);
    } catch (_err) {}
  },

  clearDraftElements() {
    // Clear draft circle
    try {
      if (this.draftCircle) {
        this.map.removeLayer(this.draftCircle);
        this.draftCircle = null;
      }
    } catch (_err) {}

    // Clear selection marker
    try {
      if (this.selectionMarker) {
        this.map.removeLayer(this.selectionMarker);
        this.selectionMarker = null;
      }
    } catch (_err) {}
  },

  getEditingId() {
    const attr = this.el.dataset.editingId;
    if (attr && attr !== "" && attr !== "nil") return attr;
    const form = document.querySelector("form[id^='edit-location-form-']");
    if (form) {
      const m = form.id.match(/edit-location-form-(.+)$/);
      if (m) return m[1];
    }
    return null;
  },

  getFireColor(confidence, frp, isRecent = true) {
    // Return gray shades for older fires
    if (!isRecent) {
      if (confidence === "h" && frp > 20) return "#4b5563"; // Dark gray
      if (confidence === "h") return "#6b7280"; // Medium gray
      if (frp > 20) return "#6b7280"; // Medium gray
      return "#9ca3af"; // Light gray
    }

    // Original colors for recent fires
    if (confidence === "h" && frp > 20) return "#dc2626"; // High confidence, high power - bright red
    if (confidence === "h") return "#f97316"; // High confidence - orange
    if (frp > 20) return "#ea580c"; // High power - dark orange
    return "#fb923c"; // Normal - light orange
  },

  getClusterColor(count, avgIntensity, recentRatio = 1.0) {
    // Calculate cluster color based on fire count, average intensity, and recent fire ratio
    // avgIntensity is a score from 0-100 based on FRP and confidence
    // recentRatio is 0-1, where 1.0 = all recent fires, 0 = all older fires

    // Base intensity on fire count
    let baseIntensity;
    if (count >= 50) baseIntensity = 1.0;
    else if (count >= 20) baseIntensity = 0.9;
    else if (count >= 10) baseIntensity = 0.8;
    else if (count >= 5) baseIntensity = 0.7;
    else baseIntensity = 0.6;

    // Adjust for average fire intensity (0-100 scale)
    const intensityMultiplier = 0.5 + avgIntensity / 200; // 0.5 to 1.0
    let finalIntensity = Math.min(1.0, baseIntensity * intensityMultiplier);

    // If cluster has at least 1 recent fire, make it red, otherwise gray
    if (recentRatio > 0) {
      // Has recent fires - use red tones
      const red = Math.round(139 + 116 * finalIntensity); // 139 to 255
      const green = Math.round(26 * (1 - finalIntensity * 0.8)); // 26 to ~5
      const blue = Math.round(26 * (1 - finalIntensity * 0.8)); // 26 to ~5
      return `rgb(${red}, ${green}, ${blue})`;
    } else {
      // No recent fires - use gray tones
      const grayIntensity = Math.round(107 + 48 * finalIntensity); // 107 to 155 (gray range)
      return `rgb(${grayIntensity}, ${grayIntensity}, ${grayIntensity})`;
    }
  },

  calculateFireIntensity(fireData) {
    // Calculate intensity score (0-100) based on FRP and confidence
    let score = 0;

    // FRP contribution (0-70 points)
    const frp = fireData.frp || 0;
    if (frp > 50) score += 70;
    else if (frp > 20) score += 50 + ((frp - 20) / 30) * 20;
    else if (frp > 5) score += 30 + ((frp - 5) / 15) * 20;
    else score += (frp / 5) * 30;

    // Confidence contribution (0-30 points)
    const confidence = fireData.confidence || "n";
    if (confidence === "h") score += 30;
    else if (confidence === "n") score += 15;
    else score += 5; // low confidence

    return Math.min(100, score);
  },

  createFireClusterIcon(cluster) {
    const markers = cluster.getAllChildMarkers();
    const count = markers.length;

    // Calculate average intensity and recent fire ratio
    let totalIntensity = 0;
    let validMarkers = 0;
    let recentCount = 0;

    markers.forEach((marker) => {
      if (marker.fireData) {
        totalIntensity += this.calculateFireIntensity(marker.fireData);
        validMarkers++;
        if (marker.fireData.isRecent) {
          recentCount++;
        }
      }
    });

    const avgIntensity = validMarkers > 0 ? totalIntensity / validMarkers : 50;
    const recentRatio = validMarkers > 0 ? recentCount / validMarkers : 0;
    const color = this.getClusterColor(count, avgIntensity, recentRatio);

    // Size based on count
    let size;
    if (count >= 100) size = 50;
    else if (count >= 50) size = 45;
    else if (count >= 20) size = 40;
    else if (count >= 10) size = 35;
    else size = 30;

    return L.divIcon({
      html: `<div style="
        width: ${size}px;
        height: ${size}px;
        background-color: ${color};
        border: 2px solid #7f1d1d;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        font-weight: bold;
        font-size: ${Math.max(12, size * 0.4)}px;
        text-shadow: 1px 1px 1px rgba(0,0,0,0.7);
        box-shadow: 0 2px 8px rgba(0,0,0,0.3);
      ">🔥</div>`,
      className: "fire-cluster-icon",
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    });
  },

  getZoomForRadius(radiusMeters) {
    // Approximate zoom levels for different radius sizes
    if (radiusMeters > 50000) return 8; // > 50km
    if (radiusMeters > 20000) return 10; // > 20km
    if (radiusMeters > 10000) return 11; // > 10km
    if (radiusMeters > 5000) return 12; // > 5km
    if (radiusMeters > 2000) return 13; // > 2km
    return 14; // < 2km
  },
};

Hooks.WebPushRegistration = {
  mounted() {
    console.log("WebPushRegistration hook mounted");

    // Function to initialize the hook when elements are ready
    const initializeHook = () => {
      console.log("Initializing hook...");

      const registerBtn = this.el.querySelector("#register-push-button");
      const deviceNameInput = this.el.querySelector("#device-name");
      const statusDiv = this.el.querySelector("#push-status");

      console.log("Register button found:", !!registerBtn);
      console.log("Device name input found:", !!deviceNameInput);
      console.log("Status div found:", !!statusDiv);

      if (!registerBtn) {
        console.error("Register button not found, retrying...");
        return false;
      }

      if (!statusDiv) {
        console.error("Status div not found, retrying...");
        return false;
      }

      // Test if status div is working
      // this.showStatus("Hook mounted - testing status display...", "info");

      registerBtn.addEventListener("click", async () =>
        this.handleRegisterClick()
      );

      return true;
    };

    // Try to initialize immediately
    if (!initializeHook()) {
      // If elements aren't ready, retry after a short delay
      setTimeout(() => {
        if (!initializeHook()) {
          // If still not ready, retry again
          setTimeout(initializeHook, 500);
        }
      }, 100);
    }
  },

  async handleRegisterClick() {
    const vapidKey = this.el.dataset.vapidKey;
    const registerBtn = this.el.querySelector("#register-push-button");
    const deviceNameInput = this.el.querySelector("#device-name");

    const deviceName = deviceNameInput.value.trim();
    if (!deviceName) {
      this.showError("Please enter a device name");
      return;
    }

    // Check if VAPID key is available
    if (!vapidKey || vapidKey.trim() === "") {
      this.showError(
        "VAPID key not configured. Please check server configuration."
      );
      return;
    }

    try {
      // Check if service worker and push messaging are supported
      this.showStatus("Checking browser support...", "info");

      if (!("serviceWorker" in navigator)) {
        throw new Error("Service Worker is not supported in this browser");
      }

      if (!("PushManager" in window)) {
        throw new Error("Push Manager is not supported in this browser");
      }

      if (!("Notification" in window)) {
        throw new Error("Notifications are not supported in this browser");
      }

      // Check for HTTPS requirement on mobile
      if (
        window.location.protocol !== "https:" &&
        window.location.hostname !== "localhost"
      ) {
        throw new Error(
          "Push notifications require HTTPS (except on localhost)"
        );
      }

      this.showStatus(
        "Browser support confirmed. Requesting permission...",
        "info"
      );

      // Add immediate debugging
      console.log("About to check permission status...");
      this.showStatus("About to check permission status...", "info");

      registerBtn.disabled = true;
      registerBtn.textContent = "Registering...";
      this.hideStatus();

      // Request notification permission with timeout and better error handling
      this.showStatus("Checking notification permission...", "info");

      // Check current permission status first
      const currentPermission = Notification.permission;
      this.showStatus(
        `Current permission status: ${currentPermission}`,
        "info"
      );

      // Check if we're on mobile
      const isMobile =
        /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
          navigator.userAgent
        );
      this.showStatus(
        `Device type: ${isMobile ? "Mobile" : "Desktop"}`,
        "info"
      );

      let permission;
      try {
        if (currentPermission === "granted") {
          this.showStatus(
            "Permission already granted, proceeding...",
            "success"
          );
          permission = "granted";
          // Add a small delay to make sure the user sees this message
          await new Promise((resolve) => setTimeout(resolve, 1000));
        } else if (currentPermission === "denied") {
          this.showStatus("Permission already denied by user", "error");
          throw new Error("Notification permission was previously denied");
        } else {
          // Permission is "default" - need to request it
          this.showStatus("Requesting notification permission...", "info");

          // On mobile, we might need to handle this differently
          if (isMobile) {
            this.showStatus(
              "Mobile device detected - permission request may take longer",
              "info"
            );
          }

          // Add a timeout to prevent hanging
          const permissionPromise = Notification.requestPermission();
          const timeoutPromise = new Promise((_, reject) => {
            setTimeout(
              () =>
                reject(
                  new Error("Permission request timed out after 10 seconds")
                ),
              10000
            );
          });

          permission = await Promise.race([permissionPromise, timeoutPromise]);

          this.showStatus(`Permission result: ${permission}`, "info");
        }
      } catch (error) {
        this.showStatus(`Permission request failed: ${error.message}`, "error");
        throw new Error(`Permission request failed: ${error.message}`);
      }

      if (permission !== "granted") {
        this.showStatus(`Permission denied: ${permission}`, "error");
        throw new Error(`Notification permission denied: ${permission}`);
      }

      this.showStatus(
        "Permission granted. Registering service worker...",
        "info"
      );

      // Register service worker
      const registration = await this.registerServiceWorker();

      // Wait for service worker to be active
      this.showStatus("Waiting for service worker to activate...", "info");
      if (registration.installing) {
        this.showStatus("Service worker is installing...", "info");
        await new Promise((resolve) => {
          const timeout = setTimeout(() => {
            this.showStatus(
              "Service worker installation timed out, proceeding anyway...",
              "error"
            );
            resolve();
          }, 5000);

          registration.installing.addEventListener("statechange", () => {
            this.showStatus(
              `Service worker state changed to: ${registration.installing.state}`,
              "info"
            );
            if (registration.installing.state === "activated") {
              this.showStatus("Service worker activated", "success");
              clearTimeout(timeout);
              resolve();
            }
          });
        });
      } else if (registration.waiting) {
        this.showStatus("Service worker is waiting...", "info");
        await new Promise((resolve) => {
          const timeout = setTimeout(() => {
            this.showStatus(
              "Service worker waiting timed out, proceeding anyway...",
              "error"
            );
            resolve();
          }, 5000);

          registration.waiting.addEventListener("statechange", () => {
            this.showStatus(
              `Service worker state changed to: ${registration.waiting.state}`,
              "info"
            );
            if (registration.waiting.state === "activated") {
              this.showStatus("Service worker activated", "success");
              clearTimeout(timeout);
              resolve();
            }
          });
        });
      } else if (registration.active) {
        this.showStatus("Service worker is already active", "success");
      }

      // Check for existing subscription and handle VAPID key changes
      this.showStatus("Checking for existing subscriptions...", "info");
      const shouldContinue = await this.handleExistingSubscription(
        registration,
        vapidKey
      );

      // If service worker was unregistered, re-register it
      if (!shouldContinue) {
        this.showStatus(
          "Re-registering service worker after VAPID key change...",
          "info"
        );
        const newRegistration = await this.registerServiceWorker();

        // Wait for the new service worker to be active
        if (newRegistration.installing) {
          this.showStatus(
            "Waiting for new service worker to activate...",
            "info"
          );
          await new Promise((resolve) => {
            newRegistration.installing.addEventListener("statechange", () => {
              if (newRegistration.installing.state === "activated") {
                this.showStatus("New service worker activated", "info");
                resolve();
              }
            });
          });
        }
      }

      // Subscribe to push notifications
      this.showStatus(
        "Preparing to subscribe to push notifications...",
        "info"
      );
      let applicationServerKey;
      try {
        applicationServerKey = this.urlBase64ToUint8Array(vapidKey);
      } catch (error) {
        throw new Error("Invalid VAPID key format: " + error.message);
      }

      // Check service worker state before subscription
      this.showStatus("Checking service worker state...", "info");

      if (registration.active) {
        this.showStatus(
          "Service worker is active. Attempting subscription...",
          "info"
        );
      } else {
        throw new Error(
          "Service worker is not active. Cannot subscribe to push notifications."
        );
      }

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey,
      });

      // Extract subscription details
      const subscriptionJson = subscription.toJSON();

      // Send subscription data to Phoenix (target the component, not the parent LiveView)
      this.pushEventTo(this.el.dataset.phxTarget, "register_web_push", {
        name: deviceName,
        endpoint: subscriptionJson.endpoint,
        p256dh: subscriptionJson.keys.p256dh,
        auth: subscriptionJson.keys.auth,
        user_agent: navigator.userAgent,
      });

      // Don't show success immediately - wait for Phoenix to respond
      // The success message will be shown via a flash message from the server
    } catch (error) {
      this.showError(error.message || "Failed to register device");
    } finally {
      registerBtn.disabled = false;
      registerBtn.textContent = "Enable Push Notifications";
    }
  },

  async registerServiceWorker() {
    try {
      this.showStatus("Registering service worker...", "info");

      // Check if service worker is supported
      if (!("serviceWorker" in navigator)) {
        throw new Error("Service Worker not supported");
      }

      // Register the static service worker file
      this.showStatus("Calling navigator.serviceWorker.register...", "info");
      const registration = await navigator.serviceWorker.register("/sw.js");
      this.showStatus("Service worker registered successfully", "info");

      // Check registration state
      this.showStatus(
        `Service worker state: ${
          registration.installing
            ? registration.installing.state
            : registration.active
            ? "active"
            : "unknown"
        }`,
        "info"
      );

      return registration;
    } catch (error) {
      this.showStatus(
        `Service worker registration failed: ${error.message}`,
        "error"
      );
      throw new Error(`Service worker registration failed: ${error.message}`);
    }
  },

  async handleExistingSubscription(registration, newVapidKey) {
    try {
      const existingSubscription =
        await registration.pushManager.getSubscription();

      if (existingSubscription) {
        // Store the current VAPID key in localStorage for comparison
        const storedVapidKey = localStorage.getItem("fireping_vapid_key");

        if (storedVapidKey && storedVapidKey !== newVapidKey) {
          console.log("VAPID key changed, performing complete cleanup...");

          // Unsubscribe from the old subscription
          await existingSubscription.unsubscribe();

          // Clear all caches
          const cacheNames = await caches.keys();
          await Promise.all(cacheNames.map((name) => caches.delete(name)));

          // Clear localStorage
          localStorage.removeItem("fireping_vapid_key");

          // Unregister the service worker completely
          await registration.unregister();

          console.log(
            "Complete cleanup performed, will re-register service worker"
          );

          // Return false to indicate we need to re-register
          return false;
        } else if (!storedVapidKey) {
          console.log(
            "No stored VAPID key found, unsubscribing existing subscription to ensure clean state..."
          );

          // Unsubscribe from existing subscription
          await existingSubscription.unsubscribe();

          // Clear all caches
          const cacheNames = await caches.keys();
          await Promise.all(cacheNames.map((name) => caches.delete(name)));

          // Force service worker update
          await registration.update();
        } else {
          // Same VAPID key, unsubscribe anyway to allow re-registration
          console.log(
            "Unsubscribing existing subscription to allow re-registration..."
          );
          await existingSubscription.unsubscribe();

          // Clear all caches
          const cacheNames = await caches.keys();
          await Promise.all(cacheNames.map((name) => caches.delete(name)));

          // Force service worker update
          await registration.update();
        }
      }

      // Store the new VAPID key
      localStorage.setItem("fireping_vapid_key", newVapidKey);

      console.log("VAPID key handling completed");
      return true;
    } catch (error) {
      console.error("Error handling existing subscription:", error);
      throw error;
    }
  },

  urlBase64ToUint8Array(base64String) {
    if (!base64String || typeof base64String !== "string") {
      throw new Error("VAPID key must be a non-empty string");
    }

    // Add padding if needed
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding)
      .replace(/-/g, "+")
      .replace(/_/g, "/");

    let rawData;
    try {
      rawData = window.atob(base64);
    } catch (error) {
      throw new Error("Failed to decode base64 VAPID key: " + error.message);
    }

    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }

    // VAPID keys should be 65 bytes for uncompressed P-256 keys
    if (outputArray.length !== 65) {
      console.warn(
        `VAPID key length is ${outputArray.length} bytes, expected 65 bytes for P-256 key`
      );
    }

    return outputArray;
  },

  showError(message) {
    try {
      const statusDiv = this.el.querySelector("#push-status");

      if (!statusDiv) {
        console.error(
          "Status div not found for error - using console fallback"
        );
        console.log(`[ERROR] ${message}`);
        return;
      }

      // Clear previous content
      statusDiv.innerHTML = "";

      // Create the error message element
      const messageDiv = document.createElement("div");
      messageDiv.textContent = message;
      messageDiv.className = "text-sm text-red-600 dark:text-red-400";

      // Add to status div
      statusDiv.appendChild(messageDiv);

      // Safely remove hidden class
      if (statusDiv.classList) {
        statusDiv.classList.remove("hidden");
      }
    } catch (error) {
      console.error("Error in showError:", error);
      console.log(`[ERROR FALLBACK] ${message}`);
    }
  },

  showSuccess(message) {
    try {
      const statusDiv = this.el.querySelector("#push-status");

      if (!statusDiv) {
        console.error(
          "Status div not found for success - using console fallback"
        );
        console.log(`[SUCCESS] ${message}`);
        return;
      }

      // Clear previous content
      statusDiv.innerHTML = "";

      // Create the success message element
      const messageDiv = document.createElement("div");
      messageDiv.textContent = message;
      messageDiv.className = "text-sm text-green-600 dark:text-green-400";

      // Add to status div
      statusDiv.appendChild(messageDiv);

      // Safely remove hidden class
      if (statusDiv.classList) {
        statusDiv.classList.remove("hidden");
      }
    } catch (error) {
      console.error("Error in showSuccess:", error);
      console.log(`[SUCCESS FALLBACK] ${message}`);
    }
  },

  hideStatus() {
    try {
      const statusDiv = this.el.querySelector("#push-status");

      if (!statusDiv) {
        return;
      }

      // Safely add hidden class
      if (statusDiv.classList) {
        statusDiv.classList.add("hidden");
      }
    } catch (error) {
      console.error("Error in hideStatus:", error);
    }
  },

  showStatus(message, type = "info") {
    console.log(`showStatus called: ${message} (${type})`);

    try {
      const statusDiv = this.el.querySelector("#push-status");

      if (!statusDiv) {
        console.error("Status div not found - using console fallback");
        console.log(`[STATUS] ${message}`);
        return;
      }

      // Clear previous content
      statusDiv.innerHTML = "";

      // Create the message element
      const messageDiv = document.createElement("div");
      messageDiv.textContent = message;
      messageDiv.className = "text-sm";

      // Apply styling based on type
      if (type === "info") {
        messageDiv.className += " text-blue-600 dark:text-blue-400";
      } else if (type === "success") {
        messageDiv.className += " text-green-600 dark:text-green-400";
      } else if (type === "error") {
        messageDiv.className += " text-red-600 dark:text-red-400";
      }

      // Add to status div
      statusDiv.appendChild(messageDiv);

      // Safely remove hidden class
      if (statusDiv.classList) {
        statusDiv.classList.remove("hidden");
      }

      console.log("Status updated successfully");
    } catch (error) {
      console.error("Error in showStatus:", error);
      console.log(`[STATUS FALLBACK] ${message}`);
    }
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
