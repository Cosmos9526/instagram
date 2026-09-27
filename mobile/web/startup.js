let startupTimer;
window.studioLoadFailed = function () {
  const message = document.getElementById('startup-message');
  const retry = document.getElementById('retry');
  if (message) message.textContent = 'بارگذاری بیشتر از معمول طول کشیده است. اتصال اینترنت را بررسی کنید یا دوباره تلاش کنید.';
  if (retry) retry.hidden = false;
};
window.addEventListener('flutter-first-frame', function () {
  clearTimeout(startupTimer);
  document.getElementById('startup')?.remove();
});
startupTimer = setTimeout(window.studioLoadFailed, 20000);
