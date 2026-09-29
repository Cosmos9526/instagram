let startupTimer;
window.studioLoadFailed = function () {
  const message = document.getElementById('startup-message');
  const retry = document.getElementById('retry');
  if (message) message.textContent = 'Loading is taking longer than expected. Check your connection and try again.';
  if (retry) retry.hidden = false;
};
window.addEventListener('flutter-first-frame', function () {
  clearTimeout(startupTimer);
  document.getElementById('startup')?.remove();
});
startupTimer = setTimeout(window.studioLoadFailed, 20000);

// Remove service workers and their caches left by older builds; the app does not use them.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (rs) { rs.forEach(function (r) { r.unregister(); }); }).catch(function () {});
}
if (window.caches) {
  caches.keys().then(function (ks) { ks.forEach(function (k) { caches.delete(k); }); }).catch(function () {});
}
