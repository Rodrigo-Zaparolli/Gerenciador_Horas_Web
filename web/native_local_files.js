// Compatibility for older open pages; the versioned file owns the transport.
(() => {
  let loading;
  window.nativeLocalFilesRequest = async raw => {
    loading ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'native_local_files_v2.js';
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
    await loading;
    return window.nativeLocalFilesRequest(raw);
  };
})();
