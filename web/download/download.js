(() => {
  'use strict';
  // Match LocalLinkAnalytics._safeValue; arbitrary query text never becomes HTML.
  const safeValue = (value) => value.trim().toLowerCase().replace(/[^a-z0-9_]+/g, '_').slice(0, 100) || 'unknown';
  const rawSource = new URLSearchParams(window.location.search).get('source') || '';
  const source = safeValue(rawSource);
  const ua = navigator.userAgent || '';
  const device = /android/i.test(ua) ? 'android'
    : /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1) ? 'ios' : 'other';
  const buttons = document.getElementById('store-buttons');
  if (device === 'android') buttons.prepend(buttons.querySelector('[data-store="android"]'));
  const campaignCopy = {
    'lost-pets': 'Help your local community find and reunite missing pets.',
    'burntwood-events': 'Discover events, activities and community groups around Burntwood.',
  };
  if (Object.hasOwn(campaignCopy, rawSource)) document.getElementById('campaign-copy').textContent = campaignCopy[rawSource];

  let recordEvent = null;
  buttons.querySelectorAll('[data-store]').forEach((link) => {
    link.addEventListener('click', (event) => {
      // Plain links always work, including blocked/offline analytics and JS disabled.
      if (!recordEvent || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      let navigated = false;
      const navigate = () => { if (!navigated) { navigated = true; window.location.assign(link.href); } };
      setTimeout(navigate, 250);
      recordEvent('download_store_click', {
        store: link.dataset.store,
        transport_type: 'beacon',
        event_callback: navigate,
      });
    });
  });

  // The same Firebase web app/Analytics stream as lib/firebase_options.dart.
  // Load only Analytics, after the usable page is painted; never initialise Auth.
  async function initialiseAnalytics() {
    try {
      const [appSdk, analyticsSdk] = await Promise.all([
        import('https://www.gstatic.com/firebasejs/12.17.0/firebase-app.js'),
        import('https://www.gstatic.com/firebasejs/12.17.0/firebase-analytics.js'),
      ]);
      if (!(await analyticsSdk.isSupported())) return;
      const app = appSdk.initializeApp({
        apiKey: 'AIzaSyB1Dv3wNjBwkefxpKwRdZttnRJczDtONK4',
        appId: '1:126981571024:web:00af2a484a11a76abd39d5',
        projectId: 'locallink-995a5',
        authDomain: 'locallink-995a5.firebaseapp.com',
        messagingSenderId: '126981571024',
        measurementId: 'G-FS2QVEWMYY',
      });
      const analytics = analyticsSdk.getAnalytics(app);
      recordEvent = (name, parameters = {}) => {
        try {
          analyticsSdk.logEvent(analytics, name, {
            platform: 'web', authenticated_state: 'guest', source, device, ...parameters,
          });
        } catch (_) { /* Analytics must never block downloading. */ }
      };
      recordEvent('download_landing_view');
    } catch (_) { /* Unsupported browsers, ad blockers and offline visits are safe. */ }
  }
  initialiseAnalytics();
})();
