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

  const shots = Array.from(document.querySelectorAll("[data-hero-shot]"));
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (shots.length) {
    shots.forEach((img, idx) => img.classList.toggle("is-active", idx === 0));
  }
  if (shots.length > 1 && !reduce) {
    let i = 0;
    setInterval(() => {
      const prev = i;
      i = (i + 1) % shots.length;
      shots[i].classList.add("is-active");
      // Swap after paint so one shot stays fully opaque during the crossfade.
      requestAnimationFrame(() => {
        shots[prev].classList.remove("is-active");
      });
    }, 3200);
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
