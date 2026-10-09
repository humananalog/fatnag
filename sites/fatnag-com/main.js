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

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const heroVideo = document.querySelector(".device-video");
  if (heroVideo) {
    if (reduce) {
      heroVideo.removeAttribute("autoplay");
      heroVideo.pause();
    } else {
      const play = () => heroVideo.play().catch(() => {});
      play();
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") play();
      });
    }
  }

  if (reduce) {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-in"));
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
