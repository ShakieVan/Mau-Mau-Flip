/* Mau-Mau Flip – Entwurf A: die Mau-Katze (sitzend, schaut nach oben, Pfote am offenen Maul)
 * Box 1000×1000, Boden bei y≈966. Alles selbst gezeichnet.
 */
'use strict';

const CAT = {
  fur: '#A28A77', furLight: '#BBA593', furDark: '#86705F',
  stripe: '#4A3B36', white: '#FBF4EA', whiteShade: '#E6D8C6',
  line: '#2A2130', pink: '#E59A9B', pinkDeep: '#C97577',
  mouth: '#5A1B31', tongue: '#EA7383',
  iris1: '#F7CB5C', iris2: '#D9871C', pupil: '#1A1220',
  warm: '#FFB547', neon: '#B07CFF',
};

/* Verjüngte Streifen (Fellzeichnung): Pfad aus M..C / M..L / M..V-Abschnitten -> Füllform */
function taper(d, w, profile = 'start') {
  const segs = [];
  const re = /M\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*(?:C\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)|L\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)|V\s*(-?\d+(?:\.\d+)?))/g;
  let m;
  while ((m = re.exec(d))) {
    const v = m.slice(1).map(x => x === undefined ? null : parseFloat(x));
    const p0 = [v[0], v[1]];
    let p1, p2, p3;
    if (v[2] !== null) { p1 = [v[2], v[3]]; p2 = [v[4], v[5]]; p3 = [v[6], v[7]]; }
    else {
      p3 = v[8] !== null ? [v[8], v[9]] : [v[0], v[10]];
      p1 = [p0[0] + (p3[0] - p0[0]) / 3, p0[1] + (p3[1] - p0[1]) / 3];
      p2 = [p0[0] + 2 * (p3[0] - p0[0]) / 3, p0[1] + 2 * (p3[1] - p0[1]) / 3];
    }
    segs.push([p0, p1, p2, p3]);
  }
  const prof = t => profile === 'mid' ? Math.pow(Math.sin(Math.PI * t), 0.75) :
    profile === 'end' ? Math.pow(t, 0.85) : Math.pow(1 - t, 0.85);
  let out = '';
  for (const [a, b, c, e] of segs) {
    const N = 22, L = [], R = [];
    for (let i = 0; i <= N; i++) {
      const t = i / N, u = 1 - t;
      const x = u * u * u * a[0] + 3 * u * u * t * b[0] + 3 * u * t * t * c[0] + t * t * t * e[0];
      const y = u * u * u * a[1] + 3 * u * u * t * b[1] + 3 * u * t * t * c[1] + t * t * t * e[1];
      let dx = 3 * u * u * (b[0] - a[0]) + 6 * u * t * (c[0] - b[0]) + 3 * t * t * (e[0] - c[0]);
      let dy = 3 * u * u * (b[1] - a[1]) + 6 * u * t * (c[1] - b[1]) + 3 * t * t * (e[1] - c[1]);
      const len = Math.hypot(dx, dy) || 1; dx /= len; dy /= len;
      const hw = Math.max(0.2, w * prof(t) / 2);
      L.push([x - dy * hw, y + dx * hw]); R.push([x + dy * hw, y - dx * hw]);
    }
    const r = w / 2;
    out += 'M' + L.map(p => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('L');
    if (profile === 'end') out += `A${r} ${r} 0 0 0 ${R[N][0].toFixed(1)} ${R[N][1].toFixed(1)}`;
    out += 'L' + R.reverse().map(p => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('L');
    if (profile === 'start') out += `A${r} ${r} 0 0 0 ${L[0][0].toFixed(1)} ${L[0][1].toFixed(1)}`;
    out += 'Z';
  }
  return out;
}

function catSVG(o = {}) {
  const P = o.prefix || 'k-';
  const id = n => P + n;
  const LW = o.lineWidth || 6;          // Außenkontur
  const lw = LW * 0.6;                  // Innenlinien
  const L = CAT.line;
  const rim = o.rim !== false;

  /* ---------- Kopf (lokal, Mittelpunkt 0/0) ---------- */
  const HEAD = 'M0 -122C72 -122 130 -90 147 -30C157 2 160 34 154 58C166 68 172 80 164 90C160 96 158 98 156 102C124 132 66 148 0 148C-66 148 -124 132 -156 102C-158 98 -160 96 -164 90C-172 80 -166 68 -154 58C-160 34 -157 2 -147 -30C-130 -90 -72 -122 0 -122Z';
  const EAR_R = 'M44 -108C76 -150 116 -188 146 -204C160 -166 162 -106 148 -36C120 -66 84 -96 44 -108Z';
  const EAR_R_IN = 'M70 -106C94 -136 120 -164 140 -178C148 -146 148 -104 140 -62C120 -82 96 -98 70 -106Z';
  const mirror = d => d.replace(/(-?\d+(?:\.\d+)?)(\s+)(-?\d+(?:\.\d+)?)/g, (m, x, sp, y) => (-parseFloat(x)) + sp + y);
  const EAR_L = mirror(EAR_R), EAR_L_IN = mirror(EAR_R_IN);
  const MUZZLE = 'M0 38C-26 30 -66 38 -78 70C-88 102 -62 128 -32 138C-16 144 16 144 32 138C62 128 88 102 78 70C66 38 26 30 0 38Z';
  const MOUTH = 'M-28 66C-15 57 -6 59 0 61C6 59 15 57 28 66C31 95 17 121 0 121C-17 121 -31 95 -28 66Z';
  const NOSE = 'M-16 33C-8 28 8 28 16 33C14 44 6 50 0 53C-6 50 -14 44 -16 33Z';
  const eye = (ex, ey, s) => { // s = +1 rechtes, -1 linkes Auge (Außenwinkel außen)
    const x = v => ex + v * s;
    return `M${x(-35)} ${ey + 4}C${x(-35)} ${ey - 32} ${x(28)} ${ey - 40} ${x(38)} ${ey - 6}C${x(38)} ${ey + 28} ${x(-12)} ${ey + 36} ${x(-35)} ${ey + 4}Z`;
  };
  const EYE_R = eye(60, -10, 1), EYE_L = eye(-60, -10, -1);
  const lid = (ex, ey, s) => { const x = v => ex + v * s; return `M${x(-36)} ${ey + 3}C${x(-36)} ${ey - 33} ${x(28)} ${ey - 41} ${x(40)} ${ey - 8}`; };

  // Blick nach oben rechts
  const pup = (ex, ey) => `<ellipse cx="${ex + 8}" cy="${ey - 6}" rx="16" ry="22" fill="${CAT.pupil}"/>` +
    `<circle cx="${ex + 1}" cy="${ey - 15}" r="7" fill="#FFFFFF"/><circle cx="${ex + 16}" cy="${ey + 6}" r="3" fill="#FFFFFF" opacity=".85"/>`;

  let head = '';
  // Ohren
  head += `<path d="${EAR_L}" fill="url(#${id('fell')})" stroke="${L}" stroke-width="${LW}" stroke-linejoin="round"/>`;
  head += `<path d="${EAR_R}" fill="url(#${id('fell')})" stroke="${L}" stroke-width="${LW}" stroke-linejoin="round"/>`;
  head += `<path d="${EAR_L_IN}" fill="url(#${id('ohr')})"/><path d="${EAR_R_IN}" fill="url(#${id('ohr')})"/>`;
  head += `<path d="M78 -104C90 -122 98 -136 112 -150M88 -100C104 -112 116 -122 128 -128M-78 -104C-90 -122 -98 -136 -112 -150M-88 -100C-104 -112 -116 -122 -128 -128" fill="none" stroke="${CAT.white}" stroke-width="3.2" stroke-linecap="round" opacity=".85"/>`;
  // Kopfform
  head += `<path d="${HEAD}" fill="url(#${id('fell')})" stroke="${L}" stroke-width="${LW}" stroke-linejoin="round"/>`;
  // Tigerzeichnung: das "M" auf der Stirn (M wie Mau) + Streifen
  head += `<g clip-path="url(#${id('kopfclip')})" fill="${CAT.stripe}">` +
    [['M-34 -98C-42 -86 -48 -68 -50 -44', 14, 'start'], ['M34 -98C42 -86 48 -68 50 -44', 14, 'start'],
     ['M-34 -98C-24 -82 -12 -72 0 -62', 12, 'mid'], ['M34 -98C24 -82 12 -72 0 -62', 12, 'mid'],
     ['M0 -70V-128', 12, 'end'], ['M-18 -80C-20 -98 -22 -112 -26 -128', 10, 'end'], ['M18 -80C20 -98 22 -112 26 -128', 10, 'end'],
     ['M-102 4C-120 10 -134 16 -156 16', 13, 'end'], ['M-96 26C-114 38 -130 46 -154 48', 12, 'end'],
     ['M102 4C120 10 134 16 156 16', 13, 'end'], ['M96 26C114 38 130 46 154 48', 12, 'end'],
     ['M-118 -68C-132 -58 -142 -48 -152 -34', 12, 'end'], ['M118 -68C132 -58 142 -48 152 -34', 12, 'end']]
      .map(([d, w, p]) => `<path d="${taper(d, w, p)}"/>`).join('') +
    `</g>`;
  // Schnauze
  head += `<path d="${MUZZLE}" fill="${CAT.white}"/>`;
  head += `<path d="M-60 120C-30 142 30 142 60 120" fill="none" stroke="${CAT.whiteShade}" stroke-width="5" stroke-linecap="round" clip-path="url(#${id('kopfclip')})"/>`;
  // Augen
  for (const [E, ex, ey] of [[EYE_L, -60, -10], [EYE_R, 60, -10]]) {
    const cid = id('auge' + (ex < 0 ? 'L' : 'R'));
    head += `<clipPath id="${cid}"><path d="${E}"/></clipPath>`;
    head += `<path d="${E}" fill="url(#${id('iris')})"/>`;
    head += `<g clip-path="url(#${cid})">${pup(ex, ey)}<path d="${E}" fill="none" stroke="#000" stroke-opacity=".16" stroke-width="9"/></g>`;
    head += `<path d="${E}" fill="none" stroke="${L}" stroke-width="${lw}" stroke-linejoin="round"/>`;
  }
  head += `<path d="${lid(-60, -10, -1)}" fill="none" stroke="${L}" stroke-width="${lw * 1.35}" stroke-linecap="round"/>`;
  head += `<path d="${lid(60, -10, 1)}" fill="none" stroke="${L}" stroke-width="${lw * 1.35}" stroke-linecap="round"/>`;
  // Maul (offen: "Mau")
  head += `<clipPath id="${id('maul')}"><path d="${MOUTH}"/></clipPath>`;
  head += `<path d="${MOUTH}" fill="${CAT.mouth}"/>`;
  head += `<g clip-path="url(#${id('maul')})"><ellipse cx="0" cy="116" rx="22" ry="16" fill="${CAT.tongue}"/><path d="M0 106V122" stroke="#C4566A" stroke-width="2.4"/></g>`;
  head += `<path d="M-20 63L-14 62L-17 71Z M20 63L14 62L17 71Z" fill="#FFFFFF"/>`;
  head += `<path d="${MOUTH}" fill="none" stroke="${L}" stroke-width="${lw}" stroke-linejoin="round"/>`;
  // Nase
  head += `<path d="M0 52V61" stroke="${L}" stroke-width="${lw}" stroke-linecap="round"/>`;
  head += `<path d="${NOSE}" fill="${CAT.pink}" stroke="${L}" stroke-width="${lw * 0.8}" stroke-linejoin="round"/>`;
  head += `<ellipse cx="-5" cy="36" rx="5" ry="2.6" fill="#FFFFFF" opacity=".55"/>`;
  // Schnurrhaare
  const wh = 'M-70 76C-110 62 -150 58 -200 62M-72 88C-116 86 -156 90 -204 102M-68 100C-108 112 -146 124 -190 146';
  head += `<g fill="none" stroke="${o.whisker || CAT.white}" stroke-width="3" stroke-linecap="round" opacity=".95"><path d="${wh}"/><path d="${mirror(wh)}"/></g>`;
  head += `<ellipse cx="-94" cy="60" rx="20" ry="11" fill="${CAT.pink}" opacity=".3"/><ellipse cx="94" cy="60" rx="20" ry="11" fill="${CAT.pink}" opacity=".3"/>`;

  /* ---------- Körper (global) ---------- */
  const BODY = 'M410 420C388 470 372 530 368 600C364 660 340 714 316 772C282 850 278 918 304 952C322 968 360 968 396 966L616 966C652 968 688 966 706 950C734 918 730 850 696 772C672 714 650 660 644 600C640 530 624 470 600 420Z';
  const THIGH_L = 'M322 776C366 756 410 794 414 862C418 918 404 950 384 962';
  const THIGH_R = 'M690 776C646 756 602 794 598 862C594 918 608 950 628 962';
  const THIGH_L_AREA = THIGH_L + 'L290 962L280 776Z';
  const THIGH_R_AREA = THIGH_R + 'L720 962L730 776Z';
  const BIB = 'M498 432C546 434 584 470 592 540C600 610 580 690 554 748C540 780 532 820 530 870L478 870C472 820 462 780 448 748C420 690 400 610 406 540C412 470 452 432 498 432Z';
  const LEG = 'M596 580C562 590 546 620 548 660C550 750 546 840 540 930L598 930C606 830 624 740 628 640C630 600 618 578 596 580Z';
  const LEG_LINES = 'M594 582C562 592 546 622 548 662C550 750 546 840 540 930M628 640C624 740 606 830 598 930';
  const PAW_F = 'M528 936C526 914 544 904 568 904C592 904 608 914 606 936C606 958 592 966 568 966C544 966 528 958 528 936Z';
  const PAW_HL = 'M310 952C308 934 324 924 348 924C372 924 388 934 386 952C384 966 368 970 348 970C328 970 312 966 310 952Z';
  const PAW_HR = 'M702 952C704 934 688 924 664 924C640 924 624 934 626 952C628 966 644 970 664 970C684 970 700 966 702 952Z';
  const ARM = 'M368 632C366 590 380 528 406 452C424 446 446 448 464 456C462 520 452 590 438 642C428 684 370 680 368 632Z';
  const PAW_UP = 'M404 456C394 428 408 400 434 394C448 390 460 392 468 400C476 408 474 420 466 428C470 444 460 462 440 466C424 470 410 468 404 456Z';
  const TAIL = 'M690 944C800 944 868 890 868 808C868 738 826 708 834 646C840 604 872 586 898 596';

  let body = '';
  body += `<ellipse cx="505" cy="968" rx="290" ry="18" fill="#000" opacity=".2"/>`;
  // Schwanz (hinter dem Körper)
  body += `<path d="${TAIL}" fill="none" stroke="${L}" stroke-width="${54 + LW * 2}" stroke-linecap="round"/>`;
  body += `<path d="${TAIL}" fill="none" stroke="url(#${id('fellquer')})" stroke-width="54" stroke-linecap="round"/>`;
  body += `<path d="${TAIL}" fill="none" stroke="${CAT.stripe}" stroke-width="54" stroke-dasharray="18 30" stroke-dashoffset="-20" opacity=".9"/>`;
  // Körper
  body += `<path d="${BODY}" fill="url(#${id('fellquer')})" stroke="${L}" stroke-width="${LW}" stroke-linejoin="round"/>`;
  const ST = (list) => list.map(([d, w, p]) => `<path d="${taper(d, w, p || 'start')}"/>`).join('');
  body += `<g clip-path="url(#${id('koerperclip')})" fill="${CAT.stripe}" opacity=".92">` +
    ST([['M356 600C380 606 396 620 404 642', 21], ['M344 660C368 668 386 684 394 706', 21], ['M322 718C346 728 362 744 370 766', 21],
        ['M654 600C630 606 614 620 606 642', 21], ['M666 660C642 668 624 684 616 706', 21], ['M688 718C664 728 648 744 640 766', 21],
        ['M392 446C410 458 422 476 426 498', 17], ['M618 446C600 458 588 476 584 498', 17]]) +
    `<g clip-path="url(#${id('hlclip')})">` + ST([['M290 880C316 846 356 836 404 850', 22], ['M296 930C322 904 360 900 408 912', 22], ['M300 806C324 790 352 790 384 804', 20]]) + `</g>` +
    `<g clip-path="url(#${id('hrclip')})">` + ST([['M720 880C694 846 654 836 606 850', 22], ['M714 930C688 904 650 900 602 912', 22], ['M710 806C686 790 658 790 626 804', 20]]) + `</g>` +
    `</g>`;
  body += `<path d="${THIGH_L}" fill="none" stroke="${L}" stroke-width="${lw}" stroke-linecap="round"/><path d="${THIGH_R}" fill="none" stroke="${L}" stroke-width="${lw}" stroke-linecap="round"/>`;
  // Brustlatz
  body += `<path d="${BIB}" fill="${CAT.white}"/>`;
  body += `<path d="M446 520C456 540 462 562 464 590M552 520C544 540 538 562 536 590" fill="none" stroke="${CAT.whiteShade}" stroke-width="5" stroke-linecap="round"/>`;
  // Standbein
  body += `<path d="${LEG}" fill="url(#${id('fell')})"/>`;
  body += `<g clip-path="url(#${id('beinclip')})" fill="${CAT.stripe}">${ST([['M538 724L638 714', 18, 'mid'], ['M536 786L632 778', 18, 'mid'], ['M534 848L624 842', 17, 'mid']])}</g>`;
  body += `<path d="${LEG_LINES}" fill="none" stroke="${L}" stroke-width="${lw}" stroke-linecap="round"/>`;
  // Pfoten am Boden
  for (const Pw of [PAW_HL, PAW_HR, PAW_F]) body += `<path d="${Pw}" fill="${CAT.white}" stroke="${L}" stroke-width="${lw}" stroke-linejoin="round"/>`;
  body += `<path d="M556 944V958M580 944V958M336 952V964M360 952V964M652 952V964M676 952V964" stroke="${L}" stroke-width="3.4" stroke-linecap="round" opacity=".7"/>`;
  // erhobener Arm
  body += `<path d="${ARM}" fill="url(#${id('fell')})" stroke="${L}" stroke-width="${lw * 1.3}" stroke-linejoin="round"/>`;
  body += `<g clip-path="url(#${id('armclip')})" fill="${CAT.stripe}">${ST([['M360 540L470 552', 18, 'mid'], ['M358 596L462 606', 18, 'mid']])}</g>`;

  // Kopf an Position mit Neigung
  const HX = 500, HY = 298, HR = 10;
  const headG = `<g transform="translate(${HX} ${HY}) rotate(${HR})">${head}</g>`;
  // Pfote am Maul (vor dem Kopf)
  const paw = `<path d="${PAW_UP}" fill="${CAT.white}" stroke="${L}" stroke-width="${lw * 1.3}" stroke-linejoin="round"/>` +
    `<path d="M424 398C428 408 430 418 430 428M446 396C450 404 452 412 452 420" fill="none" stroke="${L}" stroke-width="3.4" stroke-linecap="round" opacity=".7"/>`;

  // Randlicht: warm links (Sonne), Neon rechts (Mond)
  let rimL = '';
  if (rim) {
    rimL += `<g clip-path="url(#${id('silclip')})" fill="none" stroke-width="20" opacity=".85">` +
      `<g stroke="url(#${id('rand')})"><path d="${BODY}"/><path d="${ARM}"/><path d="${TAIL}" stroke-width="0"/></g>` +
      `<g transform="translate(${HX} ${HY}) rotate(${HR})" stroke="url(#${id('randkopf')})"><path d="${HEAD}"/><path d="${EAR_L}"/><path d="${EAR_R}"/></g></g>` +
      ``;
  }

  const defs = `<defs>` +
    `<linearGradient id="${id('fell')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${CAT.furLight}"/><stop offset="1" stop-color="${CAT.fur}"/></linearGradient>` +
    `<linearGradient id="${id('fellquer')}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${CAT.furLight}"/><stop offset=".55" stop-color="${CAT.fur}"/><stop offset="1" stop-color="${CAT.furDark}"/></linearGradient>` +
    `<linearGradient id="${id('ohr')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${CAT.pinkDeep}"/><stop offset="1" stop-color="${CAT.pink}"/></linearGradient>` +
    `<radialGradient id="${id('iris')}" cx=".55" cy=".45" r=".6"><stop offset="0" stop-color="${CAT.iris1}"/><stop offset="1" stop-color="${CAT.iris2}"/></radialGradient>` +
    `<linearGradient id="${id('rand')}" gradientUnits="userSpaceOnUse" x1="280" y1="0" x2="900" y2="0"><stop offset="0" stop-color="${CAT.warm}"/><stop offset=".26" stop-color="${CAT.warm}" stop-opacity="0"/><stop offset=".6" stop-color="${CAT.neon}" stop-opacity="0"/><stop offset=".78" stop-color="${CAT.neon}"/></linearGradient>` +
    `<linearGradient id="${id('randkopf')}" gradientUnits="userSpaceOnUse" x1="-220" y1="0" x2="220" y2="0"><stop offset="0" stop-color="${CAT.warm}"/><stop offset=".35" stop-color="${CAT.warm}" stop-opacity="0"/><stop offset=".65" stop-color="${CAT.neon}" stop-opacity="0"/><stop offset="1" stop-color="${CAT.neon}"/></linearGradient>` +
    `<clipPath id="${id('kopfclip')}"><path d="${HEAD}"/></clipPath>` +
    `<clipPath id="${id('koerperclip')}"><path d="${BODY}"/></clipPath>` +
    `<clipPath id="${id('hlclip')}"><path d="${THIGH_L_AREA}"/></clipPath><clipPath id="${id('hrclip')}"><path d="${THIGH_R_AREA}"/></clipPath>` +
    `<clipPath id="${id('beinclip')}"><path d="${LEG}"/></clipPath><clipPath id="${id('armclip')}"><path d="${ARM}"/></clipPath>` +
    `<clipPath id="${id('silclip')}"><path d="${BODY}"/><path d="${ARM}"/><path d="${HEAD}" transform="translate(${HX} ${HY}) rotate(${HR})"/><path d="${EAR_L}" transform="translate(${HX} ${HY}) rotate(${HR})"/><path d="${EAR_R}" transform="translate(${HX} ${HY}) rotate(${HR})"/></clipPath>` +
    `</defs>`;

  return `<g class="mau-katze">${defs}${body}${headG}${paw}${rimL}</g>`;
}

if (typeof window !== 'undefined') window.catSVG = catSVG;
