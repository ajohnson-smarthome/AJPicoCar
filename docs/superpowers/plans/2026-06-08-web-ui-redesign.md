# Редизайн веб-пульта — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Переписать `main/web/index.html` в ландшафт-геймпад раскладку, стиль Stealth/минимал, с аркадным стиком+шкалой газа, танковыми стиками, калибровкой «вид сверху» и мягкими переходами — без изменений прошивки.

**Architecture:** Один HTML-файл (вшит в прошивку через `EMBED_TXTFILES`), отдаётся HTTP-сервером и captive-порталом. Сохраняем существующую интеграцию: WebSocket `/ws` (текст `t,y`, поток 10 Гц), REST `/calib`, `/calib/spin`, `/calib/save`; математику схем; гейтинг по `/calib`; PWA-меты и иконку в `<head>`. Меняем разметку, CSS и UX-поток.

**Tech Stack:** HTML/CSS/JS (vanilla, pointer events), ESP-IDF `EMBED_TXTFILES`. Проверка — сборка + визуально на телефоне (landscape).

---

## File Structure

| Файл | Что меняется |
|---|---|
| `main/web/index.html` | Полная переработка `<style>` + `<body>`; `<head>` (PWA-меты + data-URI иконка) **сохраняется как есть** |

Прошивочные файлы, CMake, протокол — без изменений.

---

## Task 1: Переписать `main/web/index.html` (новый UI)

**Files:**
- Modify: `main/web/index.html` (заменить блок `<style>...</style>` и весь `<body>...</body>`; `<head>`-строки PWA/иконки сохранить)

- [ ] **Step 1: Сохранить PWA-`<head>`, заменить `<style>` и `<body>`**

В `main/web/index.html` **оставить без изменений** существующие строки в `<head>`: `<meta charset>`, `<meta name="viewport">`, `<title>`, все `<meta name="apple-mobile-web-app-*">`, `<meta name="theme-color">` и две строки `<link rel="apple-touch-icon"...>` / `<link rel="icon"...>` с `data:image/png;base64,...` (длинную иконку НЕ трогать).

Заменить **только** блок `<style>...</style>` на:

```html
  <style>
    :root{
      --bg:#0a0a0a; --panel:#141519; --line:#222; --line2:#262626;
      --accent:#4ade80; --muted:#777; --text:#cfcfcf;
    }
    *{box-sizing:border-box;}
    html,body{height:100%;margin:0;}
    body{background:var(--bg);color:var(--text);
         font-family:-apple-system,system-ui,sans-serif;
         overflow:hidden;touch-action:none;-webkit-user-select:none;user-select:none;}
    .hidden{display:none!important;}
    .fade{transition:opacity .2s ease;}
    button{font-family:inherit;}

    /* rotate hint (portrait) */
    #rotate{display:none;}
    @media (orientation:portrait){
      #rotate{display:flex;position:fixed;inset:0;z-index:60;background:var(--bg);
              color:var(--muted);align-items:center;justify-content:center;
              text-align:center;padding:28px;font-size:1.05rem;line-height:1.5;}
      #app{filter:blur(3px);}
    }

    /* status bar */
    .statusbar{position:fixed;top:12px;left:0;right:0;z-index:20;
               display:flex;justify-content:center;align-items:center;gap:10px;}
    .pill{display:flex;align-items:center;gap:8px;padding:6px 12px;border-radius:10px;
          background:#0f0f0f;border:1px solid var(--line);font-size:12px;color:var(--muted);}
    .pill .dot{width:8px;height:8px;border-radius:50%;background:#d4a72c;}
    .pill.on{color:var(--text);} .pill.on .dot{background:var(--accent);}
    .pill.lost{color:#c77;border-color:#2a1313;} .pill.lost .dot{background:#e35;}
    .seg{display:flex;border:1px solid var(--line);border-radius:9px;overflow:hidden;}
    .seg button{background:#0f0f0f;color:var(--muted);border:none;padding:6px 14px;font-size:12px;}
    .seg button.active{background:var(--panel);color:var(--accent);}

    /* drive */
    #drive{position:fixed;inset:0;}
    #drive.frozen .stick{opacity:.35;}
    .stick{position:absolute;bottom:26px;width:122px;height:122px;border-radius:50%;
           background:var(--panel);border:1px solid var(--line);touch-action:none;}
    .stick.left{left:34px;} .stick.right{right:34px;}
    .knob{position:absolute;top:50%;left:50%;width:54px;height:54px;margin:-27px 0 0 -27px;
          border-radius:50%;background:var(--accent);will-change:transform;}
    #throttle{position:absolute;bottom:26px;left:48px;width:16px;height:122px;border-radius:9px;
              background:var(--panel);border:1px solid var(--line);overflow:hidden;}
    #throttle .fill{position:absolute;left:0;right:0;height:0;background:var(--accent);
                    transition:height .05s linear,bottom .05s linear,top .05s linear;}
    #cog{position:absolute;top:11px;right:14px;z-index:20;background:#0f0f0f;border:1px solid var(--line);
         color:var(--muted);border-radius:8px;padding:6px 9px;font-size:14px;}

    /* calibration */
    #calib{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;
           justify-content:center;gap:12px;padding:14px;text-align:center;}
    #calib .title{font-size:14px;color:#aaa;}
    .car{position:relative;width:150px;height:188px;}
    .car .body{position:absolute;top:22px;left:28px;right:28px;bottom:22px;border-radius:20px;
               background:var(--panel);border:1px solid var(--line2);}
    .car .wind{position:absolute;top:44px;left:48px;right:48px;height:30px;border-radius:9px;background:#0e0f12;}
    .wheel{position:absolute;width:32px;height:50px;border-radius:8px;background:#1d1d1d;
           border:1px solid var(--line);color:var(--muted);font-size:11px;display:flex;
           align-items:center;justify-content:center;}
    .wheel.fl{top:6px;left:4px;} .wheel.fr{top:6px;right:4px;}
    .wheel.rl{bottom:6px;left:4px;} .wheel.rr{bottom:6px;right:4px;}
    .wheel.done{background:#16271b;border-color:#2c5; color:var(--accent);}
    .wheel.tap{background:#1f3a2a;border-color:var(--accent);color:var(--accent);}
    .calbtns{display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:center;}
    .btn{background:var(--panel);border:1px solid var(--line);color:var(--accent);
         border-radius:10px;padding:9px 16px;font-size:13px;}
    .btn.muted{color:var(--muted);} .btn:disabled{opacity:.4;}
    .msg{font-size:12px;color:var(--muted);min-height:16px;}
  </style>
```

Заменить весь `<body>...</body>` на:

```html
<body>
  <div id="rotate">Поверни телефон горизонтально 🔄<br>для управления машинкой</div>

  <div id="app">
    <!-- status -->
    <div class="statusbar" id="statusbar">
      <div class="pill" id="pill"><span class="dot"></span><span id="pillTxt">connecting…</span></div>
      <div class="seg" id="seg">
        <button data-scheme="arcade" class="active">Arcade</button>
        <button data-scheme="tank">Tank</button>
      </div>
    </div>

    <!-- ============ DRIVE ============ -->
    <section id="drive" class="fade hidden">
      <button id="cog">⚙</button>
      <!-- arcade -->
      <div id="throttle" class="arcOnly"><div class="fill" id="throttleFill"></div></div>
      <div class="stick right arcOnly" id="arcBase"><div class="knob" id="arcKnob"></div></div>
      <!-- tank -->
      <div class="stick left tankOnly hidden" id="lBase"><div class="knob" id="lKnob"></div></div>
      <div class="stick right tankOnly hidden" id="rBase"><div class="knob" id="rKnob"></div></div>
    </section>

    <!-- ============ CALIBRATION ============ -->
    <section id="calib" class="fade hidden">
      <div class="title">Какое колесо крутится? Шаг <span id="cstep">1</span>/4</div>
      <div class="car">
        <div class="body"></div><div class="wind"></div>
        <div class="wheel fl" data-c="FL">FL</div>
        <div class="wheel fr" data-c="FR">FR</div>
        <div class="wheel rl" data-c="RL">RL</div>
        <div class="wheel rr" data-c="RR">RR</div>
      </div>
      <div class="calbtns">
        <button class="btn" id="spin">▶ Spin</button>
        <span id="dirBox" class="calbtns hidden">
          <button class="btn muted" data-d="1">↑ forward</button>
          <button class="btn muted" data-d="-1">↓ back</button>
        </span>
        <button class="btn" id="save" disabled>✔ Save &amp; Drive</button>
      </div>
      <div class="msg" id="cmsg">Жми Spin и смотри, какое колесо крутится.</div>
    </section>
  </div>

  <script>
    var $=function(s){return document.querySelector(s);};
    function show(sec){ ['#drive','#calib'].forEach(function(id){ $(id).classList.add('hidden'); }); sec.classList.remove('hidden'); }

    // -------- gating --------
    fetch('/calib').then(function(r){return r.json();})
      .then(function(j){ j.calibrated ? startDrive() : startCal(); })
      .catch(function(){ startCal(); });

    // -------- WebSocket + 10Hz stream --------
    var ws, pill=$('#pill'), pillTxt=$('#pillTxt'), wsStarted=false;
    function connect(){
      ws=new WebSocket('ws://'+location.host+'/ws');
      ws.onopen=function(){ pill.className='pill on'; pillTxt.textContent='connected'; $('#drive').classList.remove('frozen'); };
      ws.onclose=function(){ pill.className='pill lost'; pillTxt.textContent='reconnecting…'; $('#drive').classList.add('frozen'); setTimeout(connect,1000); };
      ws.onerror=function(){ ws.close(); };
    }
    function send(s){ if(ws&&ws.readyState===1) ws.send(s); }

    // -------- joystick component --------
    function clamp(v){ return v<-1?-1:(v>1?1:v); }
    function makeStick(base,knob,vertical){
      var v={x:0,y:0},active=false,pid=null;
      function setKnob(dx,dy){ knob.style.transform='translate('+dx+'px,'+dy+'px)'; }
      function reset(){ v.x=0; v.y=0; setKnob(0,0); }
      function move(e){
        var r=base.getBoundingClientRect(),R=Math.min(r.width,r.height)/2;
        var dx=e.clientX-(r.left+r.width/2),dy=e.clientY-(r.top+r.height/2);
        if(vertical) dx=0;
        var d=Math.hypot(dx,dy); if(d>R){dx=dx/d*R;dy=dy/d*R;}
        setKnob(dx,dy); v.x=clamp(dx/R); v.y=clamp(dy/R);
      }
      base.addEventListener('pointerdown',function(e){active=true;pid=e.pointerId;base.setPointerCapture(pid);e.preventDefault();move(e);});
      base.addEventListener('pointermove',function(e){ if(active&&e.pointerId===pid) move(e); });
      function end(){ if(active){active=false;reset();} }
      base.addEventListener('pointerup',end); base.addEventListener('pointercancel',end);
      return v;
    }
    var arc=makeStick($('#arcBase'),$('#arcKnob'),false);
    var lft=makeStick($('#lBase'),$('#lKnob'),true);
    var rgt=makeStick($('#rBase'),$('#rKnob'),true);

    // -------- scheme --------
    var scheme=localStorage.getItem('scheme')||'arcade';
    function applyScheme(){
      var arcade=(scheme==='arcade');
      document.querySelectorAll('.arcOnly').forEach(function(e){ e.classList.toggle('hidden',!arcade); });
      document.querySelectorAll('.tankOnly').forEach(function(e){ e.classList.toggle('hidden',arcade); });
      document.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('active',b.dataset.scheme===scheme); });
    }
    document.querySelectorAll('#seg button').forEach(function(b){
      b.addEventListener('click',function(){ scheme=b.dataset.scheme; localStorage.setItem('scheme',scheme); applyScheme(); });
    });

    function command(){
      var t,y;
      if(scheme==='arcade'){ t=-arc.y; y=arc.x; }
      else { var L=-lft.y,R=-rgt.y; t=(L+R)/2; y=(L-R)/2; }
      t=clamp(t); y=clamp(y);
      // arcade throttle indicator: fill from center up (fwd) / down (back)
      var f=$('#throttleFill'); var pct=Math.abs(t)*50;
      if(t>=0){ f.style.bottom='50%'; f.style.top=''; } else { f.style.top='50%'; f.style.bottom=''; }
      f.style.height=pct+'%';
      return t.toFixed(2)+','+y.toFixed(2);
    }

    function startDrive(){
      applyScheme(); show($('#drive'));
      if(!wsStarted){ wsStarted=true; connect(); setInterval(function(){ send(command()); },100); }
    }
    $('#cog').addEventListener('click',startCal);

    // -------- calibration (top-down car) --------
    var step=0, assign={}, used={}, pendingCorner=null;
    function startCal(){ step=0; assign={}; used={}; pendingCorner=null;
      document.querySelectorAll('.wheel').forEach(function(w){ w.className='wheel '+w.dataset.c.toLowerCase(); });
      $('#save').disabled=true; $('#dirBox').classList.add('hidden');
      $('#cstep').textContent='1'; $('#cmsg').textContent='Жми Spin и смотри, какое колесо крутится.';
      show($('#calib'));
    }
    $('#spin').addEventListener('click',function(){
      fetch('/calib/spin',{method:'POST',body:step+',1'});
      $('#cmsg').textContent='Кручу мотор '+(step+1)+'… тапни колесо, что крутится.';
    });
    document.querySelectorAll('.wheel').forEach(function(w){
      w.addEventListener('click',function(){
        var c=w.dataset.c; if(used[c]) return;
        pendingCorner=c;
        document.querySelectorAll('.wheel').forEach(function(x){ if(!used[x.dataset.c]) x.classList.remove('tap'); });
        w.classList.add('tap');
        $('#dirBox').classList.remove('hidden');
        $('#cmsg').textContent='В какую сторону крутилось колесо '+c+'?';
      });
    });
    document.querySelectorAll('#dirBox button').forEach(function(b){
      b.addEventListener('click',function(){
        if(!pendingCorner) return;
        assign[pendingCorner]={pair:step,sign:parseInt(b.dataset.d,10)};
        used[pendingCorner]=true;
        var w=document.querySelector('.wheel[data-c="'+pendingCorner+'"]'); w.className='wheel '+pendingCorner.toLowerCase()+' done';
        pendingCorner=null; $('#dirBox').classList.add('hidden');
        step++;
        if(step<4){ $('#cstep').textContent=(step+1); $('#cmsg').textContent='Жми Spin для следующего мотора.'; }
        else { $('#save').disabled=false; $('#cmsg').textContent='Все 4 колеса размечены — жми Save.'; }
      });
    });
    $('#save').addEventListener('click',function(){
      var order=['FL','FR','RL','RR'];
      var body=order.map(function(c){ return assign[c].pair+':'+assign[c].sign; }).join(',');
      fetch('/calib/save',{method:'POST',body:body}).then(function(r){
        if(r.ok) startDrive(); else { $('#cmsg').textContent='Сохранение не прошло — повтори.'; startCal(); }
      }).catch(function(){ $('#cmsg').textContent='Ошибка сохранения.'; });
    });
  </script>
</body>
```

- [ ] **Step 2: Собрать (страница вшита — пересборка переэмбедит)**

Run:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py build 2>&1 | tail -5
```
Expected: `Project build complete`, без ошибок.

- [ ] **Step 3: Коммит**

```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car
git add main/web/index.html
git commit -m "feat: redesign web pult — landscape gamepad, stealth style, car-diagram calibration"
```

---

## Task 2: Прошивка и визуальная проверка (с пользователем)

**Files:** (без изменений кода — проверка)

- [ ] **Step 1: Прошить**

Сверить порт (`ls /dev/cu.usbmodem*`), остановить мост (`pkill -f esp_bridge.py`), затем:
```bash
cd /Users/adamjohnson/VSCode/esp32-p4-car && export PATH=/tmp/py313bin:$PATH && source ~/esp/esp-idf/export.sh && idf.py -p /dev/cu.usbmodem* flash 2>&1 | tail -3
```

- [ ] **Step 2: Проверить на телефоне (landscape)**

Переподключиться к `ESP32-Car`, перезагрузить `http://192.168.4.1/`. Проверить:
- в portrait — подсказка «поверни телефон»; в landscape — пульт;
- статус-плашка `connecting→connected`; переключатель Arcade/Tank;
- **аркада:** стик справа рулит (вверх=газ, лево/право=поворот), слева шкала газа заполняется; **танк:** два стика = борта;
- при закрытии вкладки/обрыве — стики гаснут, плашка `reconnecting`, машина встаёт (watchdog);
- если калибровка не сохранена (или через ⚙) — экран «вид сверху»: Spin → тап колеса → направление → Save → пульт; правит правильные колёса; переживает перезагрузку.

- [ ] **Step 3: Итерации по виду (если нужно)**

Если что-то «не так по позиционированию/красоте» — править `index.html`, пересобрать (`idf.py build`), перешить, повторить. Косметические правки коммитить отдельно.

---

## Self-Review заметки

- **Покрытие спеки:** ландшафт+Stealth+зелёный (CSS-переменные, Task 1); статус-плашка 3 состояния + гашение стиков (frozen); Arcade=стик+шкала газа, Tank=два стика; калибровка «вид сверху» (тап колеса + направление, протокол `/calib*` тот же); переходы кросс-фейд (`.fade`); portrait rotate-hint. Прошивка не тронута.
- **Сохранено:** математика схем (аркада `t=-arc.y,y=arc.x`; танк `t=(L+R)/2,y=(L-R)/2`), поток 10 Гц (`setInterval 100`), `localStorage` схемы, гейтинг `/calib`, протокол `/calib/spin`/`/calib/save` (порядок FL,FR,RL,RR), PWA-`<head>` (сохранён как есть в Step 1).
- **Калибровка-семантика:** шаг i гоняет `pair=i` (`POST /calib/spin "i,1"`); пользователь тапает реально крутившееся колесо → `assign[corner]={pair:i,sign}`; уже размеченные колёса `.done` и не тапаются. Save шлёт в порядке FL,FR,RL,RR.
- **Без хост-тестов:** чистый фронтенд; верификация — сборка + визуально на устройстве (Task 2).
