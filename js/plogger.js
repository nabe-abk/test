//##############################################################################
// plogger.js
//
//##############################################################################
//[TAB=8]
'use strict';
//##############################################################################
// 初期化処理
//##############################################################################
// Special Message
asys.set_msg({
	error:			'エラー',
	confirm:		'確認',
	cancel:			'キャンセル',
	back:			'戻る',
	server_response_error:	'サーバの応答データが異常です。'
});

//##############################################################################
// サービスルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●金額整形
////////////////////////////////////////////////////////////////////////////////
asys.printc = function(p) {
	p = p.toString();
	while(1) {
		let x = p;
		p = p.replace(/^(-?\d+)(\d\d\d)/, "$1,$2");
		if (x == p) return p;
	}
}

asys.get_price = function(price_txt) {
	return Number(price_txt.replace(/[^\-\d]/g, '')) || 0;
}	

asys.$body.on('blur change', 'input.js-price', function(evt){
	const $obj = $(evt.target);
	const val  = $obj.val().replace(/[^\-\d]/g, '');
	if (val.length) {
		$obj.val( asys.printc(val) );
	}
});

////////////////////////////////////////////////////////////////////////////////
//●ファイルの読み込み / Promise
////////////////////////////////////////////////////////////////////////////////
asys.asyncFileReader = function(method, file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = function() {
			resolve(reader.result);
		}
		reader.onerror = function() {
			reject(reader.error);
		}
		reader[method](file);
	});
}

////////////////////////////////////////////////////////////////////////////////
//●ファイルのプレビュー
////////////////////////////////////////////////////////////////////////////////
asys.view_file = async function($div, inp) {
	const type = inp.type || '';

	let $obj;
	if (type.match(/\/pdf$/i)) {	// PDF
		$obj = $('<object>').attr('data', await inp.readAsDataURL());

	} else if (type.match(/^image\//i)) {
		$obj = $('<img>').attr('src', await inp.readAsDataURL());

	} else if (type.match(/^text\//i)) {
		$obj = $('<textarea>').val( await inp.readAsText() );
		$obj.prop('readonly', true);

	} else {
		$obj = $('<div>').addClass('view-error');
		$obj.text('プレビュー未対応のファイルです');
	}
	$div.empty().append( $obj );
}

//##############################################################################
// asys.js の拡張
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●hiddenの値リセット
////////////////////////////////////////////////////////////////////////////////
asys.dom_init( function($R) {
	$R.find('input[data-default], select[data-default]').each(function(idx,dom){
		const $obj = $(dom);
		$obj.val( $obj.data('default') );
	});
});

////////////////////////////////////////////////////////////////////////////////
//【Chrome】inputmodeの設定
////////////////////////////////////////////////////////////////////////////////
asys.dom_init( function($R) {
	$R.find('input[type="number"], input[type="date"], input.js-price').attr('inputmode', 'numeric');
});

////////////////////////////////////////////////////////////////////////////////
//●checkboxの値固定
////////////////////////////////////////////////////////////////////////////////
asys.$body.on('click', 'input[type="checkbox"].js-fix', function(evt){
	evt.preventDefault();
});

////////////////////////////////////////////////////////////////////////////////
//●date入力
////////////////////////////////////////////////////////////////////////////////
(function() {
	const today = new Date();
	const Year  = today.getFullYear().toString();

	asys.$body.on('change format-date', 'input[type="text"].date', function(evt){
		const $obj = $(evt.target);
		let   val  = $obj.val() || '';

		val = val.replace(/\//g, '-');
		val = val.replace(/^(\d\d)(\d\d)$/, "$1-$2");
		val = val.replace(/^(\d{2,4})(\d\d)(\d\d$)/, "$1-$2-$3");

		const mmdd = val.match(/^(\d\d?)-(\d\d?)$/);
		if (mmdd) {
			const cur_mon = today.getMonth()+1;
			const add_y   = mmdd[1] <= cur_mon- 6 ? 1 : 0;	// 10月のとき 4月までは翌年扱い
			const sub_y   = mmdd[1] >= cur_mon+10 ? 1 : 0;	//  1月のとき11月までは前年扱い
			val  = (today.getFullYear() + add_y - sub_y) + '-' + val;

		} else if (val.match(/^\d\d-\d\d?-\d\d?$/)) {
			val  = Year.substr(0,2) + val;
		}
		const ma = val.match(/^(\d{4})-(\d\d?)-(\d\d?)$/);
		if (!ma) return;

		if (ma[1]<2000 || 9999<ma[1]) val='-';
		if (ma[2]<0    || 12  <ma[2]) val='-';
		if (ma[3]<0)                  val='-';

		if (val != '-') {
			const days = new Date(ma[1], ma[2], 0).getDate();
			if (days < ma[3]) ma[3]=days;
			val = ma[1] + '-' + ('0' + ma[2]).substr(-2) + '-' + ('0' + ma[3]).substr(-2);
		}
		$obj.val(val);

		if (ma[1] != Year)
			$obj.addClass('notice');
		else
			$obj.removeClass('notice');
	});

	asys.$body.on('keydown', 'input[type="text"].date', function(evt){
		const $obj = $(evt.target);
		if (evt.keyCode == 13) $obj.change();
	});
})();

////////////////////////////////////////////////////////////////////////////////
//●input type=date を type=text に変更
////////////////////////////////////////////////////////////////////////////////
(function() {
	let keycount=0;

	asys.$body.on('keydown', 'input[type="date"]', function(evt){
		if (2<=keycount) return;
		if (evt.keyCode != 17) {
			keycount=0; return;
		}
		keycount++;
		if (keycount<2) return;

		$('input[type="date"]:not(.js-on-change-submit)')
			.attr('type',      'text')
			.attr('maxlength', '10')
			.attr('pattern',   '^(?:|\\d{4}[\\-\\/]\\d\\d?[\\-\\/]\\d\\d?)$')
			.addClass('date');
	});
})();

//##############################################################################
// ■カメラ関連
//##############################################################################
class myCamera {
	constructor(canvas, opt = {}) {
		this.stream	= null;
		this.video      = document.createElement('video');
		this.canvas     = canvas;
		this.width      = opt.width  || 1600;
		this.height     = opt.height || 1200;
		this.longside   = Math.max(this.width, this.height);
		this.syncTiming = opt.syncTiming || 50;		// msec
		this.snapTime   = opt.snapTime   || 1000;	// msec
		this.facingMode = opt.facingMode || 'environment';
	}

	async init() {
		// square for mobile phone
		this.stream = await navigator.mediaDevices.getUserMedia({
				audio: false,
				video: {		// Square
					width:		this.longside,
					height:		this.longside,
					facingMode:	this.facingMode
				}
			});
			// if fail throw.

		this.video.srcObject = this.stream;
		await new Promise(resolve => {
			this.video.onloadedmetadata = () => resolve()
		});
	}
	changeSize(width, height) {
		const longside = Math.max(width, height);
		this.width     = width;
		this.height    = height;	
		this.longside  = longside;

		if (!this.stream) return;

		// change stream request
		const track = this.stream.getVideoTracks()[0];
		track.applyConstraints({
			width:  longside,
			height: longside
		});
	}

	startSync() {
		const func = () => {
			this.sync();
			this.syncTimer = setTimeout(func, this.syncTiming);
		}
		func();
	}
	stopSync() {
		if (this.syncTimer) clearTimeout(this.syncTimer);
		this.syncTimer = null;
	}
	sync() {
		const vw = this.video.videoWidth;
		const vh = this.video.videoHeight;
		const w  = this.width;
		const h  = this.height;

		const scale_w = w / vw;
		const scale_h = h / vh;
		const canvas  = this.canvas;

		if (scale_w < scale_h) {
			const {vsize, voffset, csize0, csize1} = this.#calc_view_size(scale_h, vw, vh, w, h);
			canvas.width  = csize0;
			canvas.height = csize1;
			canvas.getContext('2d').drawImage(this.video,
					voffset, 0, vsize, vh,
					0, 0, csize0, csize1
			);
			// console.log(vw, vh, ':', voffset, 0, vsize, vh, '-->', 0, 0, csize0, csize1);
		} else {
			const {vsize, voffset, csize0, csize1} = this.#calc_view_size(scale_w, vh, vw, h, w);
			canvas.width  = csize1;
			canvas.height = csize0;
			canvas.getContext('2d').drawImage(this.video,
					0, voffset, vw, vsize,
					0, 0, csize1, csize0
			);
			// console.log(vw, vh, ':',0, voffset, vw, vsize, '-->', 0, 0, csize1, csize0);
		}
	}
	#calc_view_size(scale, vsize0, vsize1, csize0, csize1) {
		if (1 < scale) {
			// Videoのほうが小さいときは、canvasを縮小する
			csize0 = Math.round(csize0/scale);
			csize1 = vsize1;
			scale  = 1;
		}
		const vsize   = Math.round(csize0/scale);
		const voffset = Math.floor((vsize0-vsize)/2);
		return {vsize, voffset, csize0, csize1};
	}


	play(delay) {
		if (delay) return setTimeout(() => this.play(), delay);
		this.video.play();
		this.startSync();
	}
	stop() {
		this.video.pause();
		this.stopSync();
	}
}
globalThis.myCamera = myCamera;
