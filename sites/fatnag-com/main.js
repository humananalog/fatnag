(() => {
  const y = document.getElementById("y");
  if (y) y.textContent = String(new Date().getFullYear());

  const nav = document.getElementById("nav");
  const onScroll = () => {
    if (!nav) return;
    nav.classList.toggle("is-scrolled", window.scrollY > 8);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  const video = document.getElementById("hero-video");
  const screen = video?.closest(".iphone17-screen");
  if (video && screen) {
    const markPlaying = () => screen.classList.add("is-playing");
    const tryPlay = () => {
      const p = video.play();
      if (p && typeof p.then === "function") {
        p.then(markPlaying).catch(() => {
          /* autoplay blocked — keep poster/fallback image */
        });
      }
    };
    video.addEventListener("playing", markPlaying);
    if (video.readyState >= 2) tryPlay();
    else video.addEventListener("loadeddata", tryPlay, { once: true });
  }

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-in"));
    if (video) {
      video.pause();
      video.removeAttribute("autoplay");
    }
    return;
  }

  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
  );

  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));
})();
