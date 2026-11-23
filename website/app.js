(() => {
  "use strict";

  const REPO = "Husnain-code-byte/OpenFlix";
  const FALLBACK_RELEASE_URL = `https://github.com/${REPO}/releases/latest`;

  // 1. Upfront OTT Cinema Rotating Poster Wall (preserved 42 curated Movies, TV & Anime)
  const allPosters = [
    "tt0816692", "tt15239678", "tt0468569", "tt1856101", "tt1375666", "tt15398776", "tt9362722",
    "tt0903747", "tt4574334", "tt3581920", "tt5753856", "tt11280740", "tt0944947", "tt7366338",
    "tt14986406", "tt2560140", "tt12343534", "tt9335498", "tt21209876", "tt0877057", "tt10233448",
    "tt4154796", "tt1877830", "tt10366206", "tt1160419", "tt1745960", "tt6751668", "tt7286456",
    "tt11126994", "tt2442560", "tt1190634", "tt3032476", "tt11198330", "tt8111088", "tt1196946",
    "tt0133093", "tt0137523", "tt0388629", "tt13706018", "tt7441658", "tt1355642", "tt13616990"
  ];

  const wall = document.getElementById("poster-wall");
  if (wall) {
    const colCount = 4;
    const speeds = [30, 36, 32, 38];
    const perCol = 8;

    for (let i = 0; i < colCount; i++) {
      const col = document.createElement("div");
      col.className = "poster-col " + (i % 2 === 0 ? "up" : "down");
      col.style.setProperty("--dur", `${speeds[i]}s`);

      const track = document.createElement("div");
      track.className = "poster-track";

      const start = (i * 10) % allPosters.length;
      const ids = Array.from({ length: perCol }, (_, k) => allPosters[(start + k) % allPosters.length]);

      ids.concat(ids).forEach((id, j) => {
        const tile = document.createElement("div");
        tile.className = "poster-tile";

        const img = document.createElement("img");
        img.src = `https://btttr.cc/poster-a/imdb/poster-default/${id}.jpg`;
        img.alt = "";
        img.width = 200;
        img.height = 300;
        img.decoding = "async";

        // Elevate at most 2 immediately visible top posters for LCP; deprioritize
        // initially off-screen duplicated carousel slides to avoid contention.
        if (j === 0 && i < 2) {
          img.fetchPriority = "high";
        } else if (j >= 3) {
          img.loading = "lazy";
          img.fetchPriority = "low";
        }

        img.addEventListener("load", () => img.classList.add("loaded"));
        img.addEventListener("error", () => {
          tile.style.display = "none";
        });

        tile.appendChild(img);
        track.appendChild(tile);
      });

      col.appendChild(track);
      wall.appendChild(col);
    }
  }

  // Pause / Resume control for poster deck animation
  const motionToggle = document.getElementById("poster-motion-toggle");
  if (motionToggle && wall) {
    motionToggle.addEventListener("click", () => {
      const paused = wall.classList.toggle("is-paused");
      motionToggle.setAttribute("aria-pressed", String(paused));
      motionToggle.textContent = paused ? "Play" : "Pause";
      motionToggle.setAttribute(
        "aria-label",
        paused ? "Resume poster stream animation" : "Pause poster stream animation"
      );
    });
  }

  // 2. Screenshots horizontal carousel controls
  const shotsRow = document.getElementById("shots-row");
  const scrollLeftBtn = document.getElementById("scroll-left");
  const scrollRightBtn = document.getElementById("scroll-right");
  if (shotsRow && scrollLeftBtn && scrollRightBtn) {
    scrollLeftBtn.addEventListener("click", () => {
      shotsRow.scrollBy({ left: -260, behavior: "smooth" });
    });
    scrollRightBtn.addEventListener("click", () => {
      shotsRow.scrollBy({ left: 260, behavior: "smooth" });
    });
  }

  // 3. Native <dialog> Screenshot Lightbox (indexed to DOM sequence with Prev/Next & arrows)
  const lightbox = document.getElementById("lightbox");
  const lbImg = document.getElementById("lb-img");
  const lbCaption = document.getElementById("lightbox-caption");
  const lbCounter = document.getElementById("lb-counter");
  const lbPrev = document.getElementById("lb-prev");
  const lbNext = document.getElementById("lb-next");
  const shotTriggers = Array.from(document.querySelectorAll(".device-frame"));
  let activeShotIndex = 0;

  function showLightboxAt(index) {
    if (!shotTriggers.length || !lbImg) return;
    activeShotIndex = (index + shotTriggers.length) % shotTriggers.length;
    const trigger = shotTriggers[activeShotIndex];
    const src = trigger.dataset.full || "";
    const caption = trigger.dataset.caption || "OpenFlix App Preview";
    lbImg.src = src;
    lbImg.alt = caption;
    if (lbCaption) lbCaption.textContent = caption;
    if (lbCounter) {
      const cur = String(activeShotIndex + 1).padStart(2, "0");
      const total = String(shotTriggers.length).padStart(2, "0");
      lbCounter.textContent = `${cur} / ${total}`;
    }
  }

  if (lightbox && lbImg && shotTriggers.length) {
    shotTriggers.forEach((trigger, index) => {
      trigger.addEventListener("click", () => {
        showLightboxAt(index);
        if (typeof lightbox.showModal === "function") {
          lightbox.showModal();
        } else {
          lightbox.setAttribute("open", "");
        }
      });
    });

    if (lbPrev) {
      lbPrev.addEventListener("click", () => showLightboxAt(activeShotIndex - 1));
    }
    if (lbNext) {
      lbNext.addEventListener("click", () => showLightboxAt(activeShotIndex + 1));
    }

    document.addEventListener("keydown", (event) => {
      if (!lightbox.open) return;
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        showLightboxAt(activeShotIndex - 1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        showLightboxAt(activeShotIndex + 1);
      }
    });

    // Fallback light-dismiss for browsers that do not yet support closedby="any"
    lightbox.addEventListener("click", (event) => {
      if (event.target === lightbox && typeof lightbox.close === "function") {
        lightbox.close();
      }
    });
  }

  // 4. Safe Markdown Release Notes Renderer (DOM nodes only — zero innerHTML)
  function appendInlineMarkdown(parent, text) {
    const tokenRegex = /(\*\*[^*]+\*\*|`[^`]+`)/g;
    let lastIndex = 0;
    let match;

    while ((match = tokenRegex.exec(text)) !== null) {
      if (match.index > lastIndex) {
        parent.appendChild(document.createTextNode(text.slice(lastIndex, match.index)));
      }
      const token = match[0];
      if (token.startsWith("**") && token.endsWith("**")) {
        const strong = document.createElement("strong");
        strong.textContent = token.slice(2, -2);
        parent.appendChild(strong);
      } else if (token.startsWith("`") && token.endsWith("`")) {
        const code = document.createElement("code");
        code.textContent = token.slice(1, -1);
        parent.appendChild(code);
      }
      lastIndex = tokenRegex.lastIndex;
    }

    if (lastIndex < text.length) {
      parent.appendChild(document.createTextNode(text.slice(lastIndex)));
    }
  }

  function renderReleaseNotes(container, markdown) {
    if (!container || !markdown || !markdown.trim()) return;

    const lines = markdown.replace(/\r\n/g, "\n").split("\n");
    const frag = document.createDocumentFragment();
    let currentList = null;
    let bulletCount = 0;

    const flushList = () => {
      if (currentList && currentList.childNodes.length > 0) {
        frag.appendChild(currentList);
      }
      currentList = null;
    };

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;
      // Skip raw HTML comments, horizontal rules, or markdown tables/badges
      if (
        line.startsWith("<!--") ||
        line.startsWith("---") ||
        line.startsWith("|") ||
        line.startsWith("![") ||
        line.toLowerCase().includes("full changelog")
      ) {
        continue;
      }

      const headingMatch = line.match(/^#{1,4}\s+(.+)$/);
      if (headingMatch) {
        flushList();
        const headingText = headingMatch[1].replace(/[*`]/g, "").trim();
        if (headingText && bulletCount < 14) {
          const h = document.createElement("h3");
          h.className = "changelog-subheading";
          h.textContent = headingText;
          frag.appendChild(h);
        }
        continue;
      }

      const bulletMatch = line.match(/^(?:[-*•]|\d+\.)\s+(.+)$/);
      if (bulletMatch) {
        if (bulletCount >= 14) continue;
        if (!currentList) {
          currentList = document.createElement("ul");
          currentList.className = "changelog-list";
        }
        const li = document.createElement("li");
        // Strip markdown links [label](url) down to clean label text
        const cleaned = bulletMatch[1].replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
        appendInlineMarkdown(li, cleaned);
        currentList.appendChild(li);
        bulletCount++;
        continue;
      }

      if (bulletCount < 10) {
        if (!currentList) {
          currentList = document.createElement("ul");
          currentList.className = "changelog-list";
        }
        const li = document.createElement("li");
        const cleaned = line.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
        appendInlineMarkdown(li, cleaned);
        currentList.appendChild(li);
        bulletCount++;
      }
    }

    flushList();
    if (frag.childNodes.length > 0) {
      container.replaceChildren(frag);
    }
  }

  function formatNumber(n) {
    return typeof n === "number" && Number.isFinite(n)
      ? n.toLocaleString("en-US")
      : "";
  }

  function formatSizeMb(bytes) {
    if (typeof bytes !== "number" || bytes <= 0) return "";
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatDate(iso) {
    if (!iso) return "";
    const dt = new Date(iso);
    if (Number.isNaN(dt.getTime())) return "";
    return dt.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric"
    });
  }

  // 5. 100% Automatic GitHub Release Pulling (latest release + cumulative downloads + stars)
  async function syncGitHubData() {
    const latestReq = fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" }
    })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);

    const allReleasesReq = fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`, {
      headers: { Accept: "application/vnd.github+json" }
    })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);

    const repoReq = fetch(`https://api.github.com/repos/${REPO}`, {
      headers: { Accept: "application/vnd.github+json" }
    })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);

    const [latest, allReleases, repoInfo] = await Promise.all([
      latestReq,
      allReleasesReq,
      repoReq
    ]);

    if (repoInfo && typeof repoInfo.stargazers_count === "number") {
      const starsEl = document.getElementById("github-stars-label");
      if (starsEl) {
        starsEl.textContent = `★ ${formatNumber(repoInfo.stargazers_count)}`;
      }
    }

    if (Array.isArray(allReleases)) {
      let totalDownloads = 0;
      for (const rel of allReleases) {
        const assets = Array.isArray(rel.assets) ? rel.assets : [];
        for (const asset of assets) {
          if (typeof asset.download_count === "number") {
            totalDownloads += asset.download_count;
          }
        }
      }
      const totalEl = document.getElementById("total-downloads-label");
      if (totalEl && totalDownloads > 0) {
        totalEl.textContent = `${formatNumber(totalDownloads)} TOTAL DOWNLOADS`;
      }
    }

    if (!latest) return;

    const version = latest.tag_name || latest.name || "Latest";

    document.querySelectorAll("[data-release-version]").forEach((el) => {
      el.textContent = version;
    });
    document.querySelectorAll("[data-release-badge]").forEach((el) => {
      el.textContent = `${version} Live`;
    });
    document.querySelectorAll("[data-release-badge-short]").forEach((el) => {
      el.textContent = `${version} · ANDROID 8.0+`;
    });

    const releaseDateEl = document.getElementById("release-date-pill");
    const formattedDate = formatDate(latest.published_at);
    if (releaseDateEl && formattedDate) {
      releaseDateEl.textContent = formattedDate.toUpperCase();
    }

    const releaseHtmlLink = document.getElementById("release-html-link");
    if (releaseHtmlLink && latest.html_url) {
      releaseHtmlLink.href = latest.html_url;
    }

    const assets = Array.isArray(latest.assets) ? latest.assets : [];
    const arm64 =
      assets.find((a) => /arm64[-_]?v8a.*\.apk$/i.test(a.name || "")) ||
      assets.find((a) => /\.apk$/i.test(a.name || "") && !/universal/i.test(a.name || ""));
    const universal = assets.find((a) => /universal.*\.apk$/i.test(a.name || ""));

    const heroDlLabel = document.getElementById("hero-dl-label");
    if (heroDlLabel) {
      heroDlLabel.textContent = `Download ${version} (arm64-v8a)`;
    }

    if (arm64 && arm64.browser_download_url) {
      document.querySelectorAll("[data-dl-arm64]").forEach((el) => {
        el.href = arm64.browser_download_url;
      });
      const sizeStr = formatSizeMb(arm64.size);
      const heroApkSize = document.getElementById("hero-apk-size");
      if (heroApkSize && sizeStr) {
        heroApkSize.textContent = `Signed arm64-v8a APK (${sizeStr})`;
      }
      const arm64SizePill = document.getElementById("arm64-size-pill");
      if (arm64SizePill && sizeStr) {
        arm64SizePill.textContent = sizeStr;
      }
      const arm64Count = document.getElementById("arm64-dl-count");
      if (arm64Count && typeof arm64.download_count === "number") {
        arm64Count.textContent = `${formatNumber(arm64.download_count)} downloads`;
      }
    } else {
      document.querySelectorAll("[data-dl-arm64]").forEach((el) => {
        el.href = latest.html_url || FALLBACK_RELEASE_URL;
      });
    }

    if (universal && universal.browser_download_url) {
      document.querySelectorAll("[data-dl-universal]").forEach((el) => {
        el.href = universal.browser_download_url;
      });
      const sizeStr = formatSizeMb(universal.size);
      const heroUnivSize = document.getElementById("hero-univ-size");
      if (heroUnivSize && sizeStr) {
        heroUnivSize.textContent = `(${sizeStr})`;
      }
      const univSizePill = document.getElementById("univ-size-pill");
      if (univSizePill && sizeStr) {
        univSizePill.textContent = sizeStr;
      }
      const univCount = document.getElementById("univ-dl-count");
      if (univCount && typeof universal.download_count === "number") {
        univCount.textContent = `${formatNumber(universal.download_count)} downloads`;
      }
    } else {
      document.querySelectorAll("[data-dl-universal]").forEach((el) => {
        el.href = latest.html_url || FALLBACK_RELEASE_URL;
      });
    }

    const changelogBody = document.getElementById("changelog-body");
    if (changelogBody && latest.body) {
      renderReleaseNotes(changelogBody, latest.body);
    }
  }

  syncGitHubData();
})();
