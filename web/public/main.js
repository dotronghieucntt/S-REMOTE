/* REMOTE — remote.novivo.net
   Nav dính, hiện dần khi cuộn, đọc bản phát hành thật, xác nhận điều khoản trước khi tải. */
(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ── Nav: đổi nền khi cuộn + menu mobile ──────────────────────────────────
  var nav = document.getElementById('nav');
  var onScroll = function () {
    nav.classList.toggle('is-scrolled', window.scrollY > 12);
  };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  var burger = document.getElementById('burger');
  var links = document.querySelector('.nav__links');
  burger.addEventListener('click', function () {
    var open = links.classList.toggle('is-open');
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Đóng menu' : 'Mở menu');
  });
  links.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') {
      links.classList.remove('is-open');
      burger.setAttribute('aria-expanded', 'false');
    }
  });

  // ── Hiện dần khi cuộn tới ────────────────────────────────────────────────
  var targets = document.querySelectorAll('.reveal');
  if (reduceMotion || !('IntersectionObserver' in window)) {
    targets.forEach(function (el) { el.classList.add('is-in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry, i) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        setTimeout(function () { el.classList.add('is-in'); }, Math.min(i * 60, 240));
        io.unobserve(el);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    targets.forEach(function (el) { io.observe(el); });
  }

  // ── Thông tin bản phát hành thật từ máy chủ ──────────────────────────────
  var setAll = function (attr, value) {
    document.querySelectorAll('[' + attr + ']').forEach(function (el) {
      el.textContent = value;
    });
  };

  fetch('/api/release', { headers: { Accept: 'application/json' } })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (rel) {
      if (rel.version) setAll('data-version', rel.version);

      if (rel.exe) {
        setAll('data-size-exe', rel.exe.sizeText);
        setAll('data-sha-exe', rel.exe.sha256);
      } else {
        setAll('data-sha-exe', 'Bản EXE đang được cập nhật.');
      }

      if (rel.zip) {
        setAll('data-size-zip', rel.zip.sizeText);
        setAll('data-sha-zip', rel.zip.sha256);
      } else {
        setAll('data-sha-zip', 'Bản Full đang được cập nhật.');
      }

      if (rel.updatedAt) {
        var d = new Date(rel.updatedAt);
        setAll('data-updated', d.toLocaleDateString('vi-VN', {
          day: '2-digit', month: '2-digit', year: 'numeric'
        }));
      }

      var n = Number(rel.downloads) || 0;
      setAll('data-downloads', n > 0 ? n.toLocaleString('vi-VN') : '—');

      // Máy chủ tự chặn gói cài có nhúng bí mật -> báo cho người xem biết,
      // đừng để họ bấm rồi ăn lỗi 503 không hiểu vì sao.
      var blocked = (rel.exe && rel.exe.blocked) || (rel.zip && rel.zip.blocked);
      if (blocked || !rel.available) showReleaseNotice(blocked);
    })
    .catch(function () {
      setAll('data-sha-exe', 'Không đọc được mã băm — thử tải lại trang.');
      setAll('data-sha-zip', 'Không đọc được mã băm — thử tải lại trang.');
    });

  // ── Bản phát hành bị gỡ: khoá nút tải và nói rõ lý do ────────────────────
  function showReleaseNotice(blocked) {
    document.querySelectorAll('a[href^="/download"], a[href^="/tai-ve"]').forEach(function (a) {
      a.classList.add('is-disabled');
      a.setAttribute('aria-disabled', 'true');
      a.addEventListener('click', function (e) { e.preventDefault(); });
    });

    var host = document.querySelector('.hero__copy');
    if (!host || document.getElementById('release-notice')) return;
    var box = document.createElement('div');
    box.id = 'release-notice';
    box.className = 'callout callout--warn';
    box.style.marginTop = '26px';
    box.innerHTML = blocked
      ? '<b>Bản tải tạm thời được gỡ.</b> Gói cài đặt hiện có chứa thông tin nhạy cảm bị lọt vào lúc đóng gói, ' +
        'nên máy chủ tự chặn phát hành. Một bản build sạch sẽ được đăng lại — cảm ơn bạn đã kiên nhẫn.'
      : '<b>Đang cập nhật bản cài đặt.</b> Vui lòng quay lại sau ít phút.';
    host.appendChild(box);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Xác nhận điều khoản trước khi tải (clickwrap)
  //  Hỏi MỘT lần cho mỗi phiên bản điều khoản, ghi nhớ trong localStorage.
  //  Đổi TERMS_VERSION khi sửa nội dung pháp lý -> người dùng cũ được hỏi lại.
  // ══════════════════════════════════════════════════════════════════════
  var TERMS_VERSION = '1.0-20260904';
  var STORE_KEY = 'remote.novivo.terms';

  function acceptedTerms() {
    try {
      var raw = JSON.parse(localStorage.getItem(STORE_KEY) || 'null');
      return !!raw && raw.version === TERMS_VERSION;
    } catch (e) {
      return false;
    }
  }

  function rememberAccept() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify({
        version: TERMS_VERSION,
        at: new Date().toISOString()
      }));
    } catch (e) { /* không lưu được thì lần sau hỏi lại */ }
  }

  var modal = null;
  var lastFocus = null;
  var pendingHref = '/download';

  function buildModal() {
    var el = document.createElement('div');
    el.className = 'modal';
    el.id = 'consent';
    el.hidden = true;
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-labelledby', 'consent-title');
    el.innerHTML = [
      '<div class="modal__veil" data-close></div>',
      '<div class="modal__box">',
      '  <div class="modal__cap">',
      '    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6l7-3z"/><path d="M9 12l2 2 4-4"/></svg>',
      '    Trước khi tải',
      '  </div>',
      '  <h2 id="consent-title">Ba điều cần rõ trước đã</h2>',
      '  <p class="modal__lead">Công cụ này thay đổi cấu hình hệ thống và mở đường vào máy của bạn. Đọc mười giây rồi hãy tải.</p>',
      '  <ul class="modal__points">',
      '    <li><i>1</i><span><b>Chỉ chạy trên máy bạn có quyền.</b> Công cụ cần quyền Administrator, sửa registry, dịch vụ, tường lửa và tạo tài khoản. Dùng lên máy người khác khi chưa được phép là hành vi truy cập trái phép.</span></li>',
      '    <li><i>2</i><span><b>Giấy phép Windows là trách nhiệm của bạn.</b> Windows Pro chỉ cho một phiên từ xa; nhiều phiên đồng thời cần Windows Server kèm RDS CAL. Phần mở khoá đa phiên trên bản client trái điều kiện giấy phép của Microsoft.</span></li>',
      '    <li><i>3</i><span><b>Có rủi ro mất kết nối.</b> Bước khởi động lại dịch vụ có thể ngắt phiên từ xa đang dùng. Hãy kết nối thử trước khi rời máy hoặc rút màn hình.</span></li>',
      '  </ul>',
      '  <label class="modal__agree">',
      '    <input type="checkbox" id="consent-check">',
      '    <span>Tôi đã đọc và đồng ý <a href="/dieu-khoan" target="_blank" rel="noopener">Điều khoản sử dụng</a> và <a href="/mien-tru-trach-nhiem" target="_blank" rel="noopener">Tuyên bố miễn trừ trách nhiệm</a>, xác nhận có quyền quản trị hợp pháp với máy sẽ cài và sẽ tuân thủ giấy phép Windows.</span>',
      '  </label>',
      '  <div class="modal__actions">',
      '    <button type="button" class="btn btn--primary" id="consent-ok" disabled>Đồng ý &amp; tải về</button>',
      '    <button type="button" class="btn btn--ghost" data-close>Để sau</button>',
      '  </div>',
      '  <p class="modal__foot">Lựa chọn được lưu ngay trên trình duyệt của bạn, không gửi về máy chủ. Lần sau bấm tải sẽ không hỏi lại, trừ khi nội dung pháp lý được cập nhật.</p>',
      '</div>'
    ].join('');
    document.body.appendChild(el);

    var check = el.querySelector('#consent-check');
    var ok = el.querySelector('#consent-ok');

    check.addEventListener('change', function () { ok.disabled = !check.checked; });
    ok.addEventListener('click', function () {
      if (!check.checked) return;
      rememberAccept();
      closeModal();
      bumpCounter();
      window.location.href = pendingHref;
    });
    el.querySelectorAll('[data-close]').forEach(function (b) {
      b.addEventListener('click', closeModal);
    });
    return el;
  }

  function openModal(href) {
    pendingHref = href || '/download';
    if (!modal) modal = buildModal();
    lastFocus = document.activeElement;
    modal.hidden = false;
    document.body.style.overflow = 'hidden';
    var check = modal.querySelector('#consent-check');
    check.checked = false;
    modal.querySelector('#consent-ok').disabled = true;
    check.focus();
  }

  function closeModal() {
    if (!modal || modal.hidden) return;
    modal.hidden = true;
    document.body.style.overflow = '';
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') closeModal();
  });

  // Chặn mọi liên kết tải xuống cho tới khi người dùng xác nhận
  var DL_SELECTOR = 'a[href="/download"], a[href="/download-full"], a[href="/tai-ve"], a[href="/tai-ve-full"]';
  document.addEventListener('click', function (e) {
    var link = e.target.closest && e.target.closest(DL_SELECTOR);
    if (!link) return;
    if (link.classList.contains('is-disabled')) { e.preventDefault(); return; }
    if (acceptedTerms()) return;      // đã đồng ý trước đó -> tải thẳng
    e.preventDefault();
    openModal(link.getAttribute('href'));
  });

  // Cờ QA: mở thẳng hộp xác nhận để xem giao diện
  if (location.search.indexOf('consent=preview') !== -1) {
    openModal('/download');
    if (location.search.indexOf('checked=1') !== -1) {
      var c = modal.querySelector('#consent-check');
      c.checked = true;
      c.dispatchEvent(new Event('change'));
    }
  }

  // ── Đếm lượt tải trên giao diện — chỉ khi lượt tải thật sự bắt đầu ───────
  function bumpCounter() {
    document.querySelectorAll('[data-downloads]').forEach(function (el) {
      var cur = parseInt(el.textContent.replace(/\D/g, ''), 10);
      if (!Number.isNaN(cur)) el.textContent = (cur + 1).toLocaleString('vi-VN');
    });
  }

  document.querySelectorAll('[data-dl]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      if (acceptedTerms()) bumpCounter();
    });
  });

  // ── Mục lục trang pháp lý: tô sáng mục đang đọc ──────────────────────────
  var tocLinks = document.querySelectorAll('.toc a[href^="#"]');
  if (tocLinks.length && 'IntersectionObserver' in window) {
    var byId = {};
    tocLinks.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });

    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        tocLinks.forEach(function (a) { a.classList.remove('is-active'); });
        var link = byId[e.target.id];
        if (link) link.classList.add('is-active');
      });
    }, { rootMargin: '-15% 0px -70% 0px', threshold: 0 });

    Object.keys(byId).forEach(function (id) {
      var sec = document.getElementById(id);
      if (sec) spy.observe(sec);
    });
  }

  // ── Năm hiện tại ở chân trang ────────────────────────────────────────────
  setAll('data-year', String(new Date().getFullYear()));
})();
