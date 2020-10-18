// control.js for test of simepidemic
// © Tatsuo Unemi, 2020
var browserID, processID, evntSrc, setupBtn, quitBtn, chngBtn;
//
function setup() {
	browserID = location.search.substring(1);
	const forms = document.forms;
	for (var i = 0; i < forms.length; i ++) {
		const elm = document.createElement('input');
		elm.type = 'hidden';
		elm.name = 'me';
		elm.value = browserID;
		forms[i].appendChild(elm);
	}
	setupBtn = document.getElementById("startMonitor");
	quitBtn = document.getElementById("stopMonitor");
	chngBtn = document.getElementById("changeMonitor");
	drawWorld(null);
}
function configRequest(com) {
	let request = "/" + com + '?report=["step"';
	const cboxes = document.getElementById("cboxes1").children;
	for (var i = 0; i < cboxes.length; i ++)
		if (cboxes[i].checked) request += ',"' + cboxes[i].name + '"';
	return request + "]&interval=" + document.getElementById("interval").value;
}
function startMonitor() {
	if (evntSrc != null) evntSrc.close();
	evntSrc = new EventSource(configRequest("periodicReport") + "&me=" + browserID);
	evntSrc.addEventListener("process", function(e) {
		processID = e.data;
		document.getElementById("procID").innerHTML = processID;
	}, false);
	evntSrc.addEventListener("population", drawWorld, false);
	evntSrc.onmessage = function (e) {
		document.getElementById("monitorText").innerHTML = e.data;
	}
	setupBtn.disabled = 1;
	quitBtn.disabled = chngBtn.disabled = 0;
}
function stopMonitor() {
	document.getElementById("controlResult").src = "/quitReport?process=" + processID;
	setupBtn.disabled = 0;
	quitBtn.disabled = chngBtn.disabled = 1;
	evntSrc.close();
	evntSrc = null;
}
function changeMonitor() {
	document.getElementById("controlResult").src =
		configRequest("changeReport") + "&process=" + processID;
}
const colors = ["#27559A", "#F6D600", "#FA302E", "#207864", "#B6B6B6",
	"#000000", "#400000", "#333333", "#FFFFFF", "#404000"];
const Susce = 0, Asymp = 1, Sympt = 2, Recov = 3, Died = 4,
	BGClr = 5, HsClr = 6, CmClr = 7, TxClr = 8, GtClr = 9;
function drawWorld(e) {
	const canvas = document.getElementById("world");
	const ctx = canvas.getContext("2d");
	const h = canvas.height;
	ctx.fillStyle = colors[BGClr];
	ctx.fillRect(0, 0, h, h);
	ctx.fillStyle = colors[HsClr];
	ctx.fillRect(h, 0, h*.2, h*.5);
	ctx.fillStyle = colors[CmClr];
	ctx.fillRect(h, h*.5, h*.2, h*.5);
	if (e == null) return;
	ctx.save();
	const scl = canvas.height * 1e-4;
	ctx.translate(0, canvas.height);
	ctx.scale(scl, -scl);
	const data = JSON.parse(e.data);
	for (let i = 0; i < 5; i ++) {
		ctx.fillStyle = colors[i];
		ctx.beginPath();
		data.forEach(function (v) {
			if (v[2] == i) ctx.rect(v[0], v[1], 20, 20);
		});
		ctx.fill();
	}
	ctx.restore();
}

