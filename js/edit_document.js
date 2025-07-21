//##############################################################################
// edit document
//
//##############################################################################
//[TAB=8]
'use strict';
//##############################################################################
//■ファイルアップロード関連
//##############################################################################
const $files   = $('#tbody-files');
const $upload  = $('#upload-templates');
let up_counter = 0;

function add_upload() {
	const c   = up_counter.toString();
	const $up = $upload.clone();

	$up.find('*').each(function(idx, dom){
		const $obj = $(dom);
		if ($obj.data('target')) $obj.data('target', $obj.data('target') + c);
		if ($obj.attr('id')    ) $obj.attr('id',     $obj.attr('id')     + c);
	});
	$up.find('button.view').hide();
	$up.removeClass('hide');
	$up.addClass('last-upload');
	$up.attr('id', '');
	$files.append($up);
	$files.find('select.camera-view-size').val($upload.find('select.camera-view-size').val());

	up_counter++;
}
add_upload();

// ファイルが選択されたら、画像サムネイルを削除する
$files.on('change', 'input.doc-file', async function(){
	const $obj = $(this);
	if (!$obj.val()) return;

	$obj.closest('tr').find('img.camera-thumbnail').remove();
});

// 最後の行のファイルが選択されたら、新しい行を追加する
$files.on('change', 'tr.last-upload input.doc-file, tr.last-upload img.camera-thumbnail', function(evt){
	const $obj = $(evt.target);
	if ($obj.is('input.doc-file') && !$obj.val()) return;

	const $tr = $obj.closest('tr');
	$tr.find('span.camera-info').remove();

	$tr.find('button.reset-file').show();
	$tr.find('button.view').show();
	$tr.removeClass('last-upload');
	add_upload();
});

// 最後の行以外がクリアされたら、行を削除する
$files.on('click', 'tr:not(.last-upload) button.reset-file', function(evt){
	const $obj = $(evt.target);
	$obj.closest('tr').remove();
});

////////////////////////////////////////////////////////////////////////////////
//●選択されたファイル名をプレビュー表示
////////////////////////////////////////////////////////////////////////////////
const $view_file = $('#view-file');
let $td_current_view;

function view_form_file(file) {
	asys.view_file($view_file, {
		readAsDataURL: function(){
			return asys.asyncFileReader('readAsDataURL', file);
		},
		readAsText: function(){
			return asys.asyncFileReader('readAsText', file);
		},
		type: file.type
	});
}

function view_camera_img(data) {
	asys.view_file($view_file, {
		readAsDataURL: () => data,
		type: 'image/jpeg'
	});
}

$files.on('change', 'input.doc-file', async function(){
	const $td = $(this).closest('td')
	const file = this.files[0];
	if (!file) return;
	//if ($td.is($td_current_view)) return;

	view_form_file(file);
	$td_current_view = $td;
	$td.find('img.camera-thumbnail').remove();
});

$files.on('click', 'td.file', async function(evt){
	const tag = evt.target.tagName;
	if (tag=='BUTTON' || tag=='A') return;

	const $td = $(this);
	if ($td.is($td_current_view)) return;

	const $img = $td.find('img.camera-thumbnail');
	if ($img.length) {
		view_camera_img($img.attr('src'));
		$td_current_view = $td;
		return;
	}

	const $file = $td.find('input.doc-file');
	if ($file.length) {
		const files = $file[0].files;
		if (!files.length) return;
		view_form_file(files[0]);
		$td_current_view = $td;
		return;
	}

	const url = $td.find('a.filepath').attr('href');
	if (!url) return;
	const res = await fetch(url);

	asys.view_file($view_file, {
		readAsDataURL: async function(){
			const blob = await res.blob();
			return URL.createObjectURL(blob);
		},
		readAsText: function(){
			return res.text();
		},
		type: res.headers.get("Content-Type")
	});
	$td_current_view = $td;
});

// 最初のファイルを自動表示
if (1) {
	const $file = $files.find('td.file');
	if ($file.length) $($file[0]).click();
}

// 表示中のファイルをリセットしたら表示クリア
$files.on('click', 'tr:not(.last-upload) button.reset-file', function(){
	const $td = $(this).closest('td');
	if ($td.is($td_current_view)) $view_file.empty();
});

////////////////////////////////////////////////////////////////////////////////
//●選択されたファイル名から、日付等を自動設定
////////////////////////////////////////////////////////////////////////////////
const dformats = [];

if (1) {
	const $dformat = $('#dformat');
	$dformat.find('option').each(function(idx,dom) {
		const $obj = $(dom);
		const val  = $obj.val();
		if (val) dformats.push(val);
	});
}

$files.on('change', 'input.doc-file', async function(evt){
	const file = evt.target.files[0];
	if (!file) return;
	if (!$('#auto-set-by-filename').prop('checked')) return;

	const name = file.name;
	const m  = name.match(/(\d\d\d\d)(\d\d)(\d\d)/)
		|| name.match(/(\d\d\d\d)[\-\/年](\d?\d)[\-\/月](\d?\d)日?/);
	if (m) {
		$('#ymd').val(m[1] + '-' + ('0' + m[2]).substr(-2) + '-' + ('0' + m[3]).substr(-2));
	}

	const name_sp  = special_alias(name);
	const $dformat = $('#dformat');
	for(const val of dformats) {
		const v = special_alias(val);
		if (0 <= name_sp.indexOf(v))
			$dformat.val(val).change();
	}

	function special_alias(str) {
		return str
			.replace('受注', '発注')
			.replace('受注', '注文')
			.replace('書', '')
		;
	}
});

////////////////////////////////////////////////////////////////////////////////
//●選択されたファイルの中身を解析
////////////////////////////////////////////////////////////////////////////////
if (1) {
	let pdfjs_path;
	$('head script').each(function(idx, dom){
		const $obj = $(dom);
		const src  = $obj.attr('src');
		if (!src) return;
		const m = src.match(/^(.*\/)pdf.\mjs(?:\?|$)/);
		if (m) {
			pdfjs_path = m[1];
		}
	});
	if (pdfjs_path) {
		pdfjsLib.GlobalWorkerOptions.workerSrc = pdfjs_path + 'pdf.worker.mjs';
	}
}

$files.on('change', 'input.doc-file', async function(evt){
	const file = evt.target.files[0];
	if (!file) return;
	if (!$('#auto-set-by-content').prop('checked')) return;

	let text='';

	if (file.type.match(/^text\//i)) {
		text = await asys.asyncFileReader('readAsText', file);

	} else if (file.type.match(/\/pdf$/i)) {
		const data = await asys.asyncFileReader('readAsArrayBuffer', file);
		const task = pdfjsLib.getDocument({ data: data });
		const pdf  = await task.promise;

		for(let p=1; p<=pdf.numPages; p++) {
			const page    = await pdf.getPage(p);
 			const content = await page.getTextContent({ includeMarkedContent: false });
			let ary = [];
 			for(const i of content.items) {
 				const str = i.str;
 				if (!str || str.match(/^\s*$/)) continue;
 				ary.push({
 					str: str,
 					x: i.transform[4],
 					y: i.transform[5]
 				});
 			}
			ary.sort((a,b) => {	// 左上から右下へ並べる
				return (b.y - a.y) || (a.x - b.x);
	 		});
	 		let y;
	 		for(const i of ary) {
	 			text	+= (i.y == y ? ' ' : (y ? "\n" : ''))
	 				+ i.str.replace(/[\s　]/g, '');
	 			y = i.y;
	 		}
	 		text += "\n";
		}
	} else {
			return;		// not support
	}

	//------------------------------------------------------------
	// テキストの前処理
	//------------------------------------------------------------
	text = text
		.normalize('NFKC')
		.tr('０-９￥％' , '0-9\\%')
		.replace(/\xE2\xBF[\xB0-\xBF]/, '')
		.replace(/注\s*文\s*書/g, '発注書')
		.replace(/利用明細書?/g, '明細書')
		.replace(/[\\\xA5](\d{1,3}(?:,\d\d\d)*)/g, "$1円")		// \xA5 = "\"
		.replace(/(税額)(\d+%|[^\d])*(\d{1,3}(?:,\d\d\d)*)円?/g, "$1$2$3円")
		.replace(/(小計|合計額|額)[^\d]*(\d{1,3}(?:,\d\d\d)*)円?(\s|$)/g, "$1$2円$3")
		.replace(/(\d) (円)/g, "$1$2");

	// デバッグ用出力
	if (false) {
		const $body = asys.$body;
		$body.find('div.debug-box').remove();
		const $div = $('<div>').addClass('debug-box').text(text);
		$body.append($div);
	}

	//------------------------------------------------------------
	// 日付、書式、相手先の名前やTELでマッチングを取る。
	// 金額情報から総額などを解析する。
	//------------------------------------------------------------
	const clist = JSON.parse($('#client-list').text());
	for(const c of clist) {
		c.keywords = c.keywords.split(' ');
	}

	const ymd_list = [];
	let dformat;
	let name_c;
	let tnumber_c;
	let tel_c;
	let tax_rate;
	let pinfo={};	// 価格情報
	let ptotal;	// 総額情報
	let pgoukei;	// 合計額
	let intax;	// 内税額
	let discount;	// 値引き
	//
	// 最後の行から最初の行へ向けてマッチングする。
	// ※上に書かれていることを優先するため
	//
	const txtary = text.split('\n').reverse();
	for(const line_space of txtary) {
		const line = line_space.replaceAll(' ', '');

		if (1) {	// 日付判定2025年2⽉10⽇
			const m  = line.match(/(\d\d\d\d)年(\d+)月(\d+)日/)
				|| line.match(/(\d\d\d\d)[\-\/](\d\d)[\-\/](\d\d)/)
			if (m && 2000<m[1] && m[2]<13 && m[3]<32) {
				const ymd = m[1] + '-' + ('0' + m[2]).substr(-2) + '-' + ('0' + m[3]).substr(-2);
				ymd_list.push(ymd);
			}
		}

		for(const x of dformats) {
			if (0 <= line.indexOf(x)) {
				if (dformat=='請求書' && x=='納品書') continue;	// 納品・請求書は請求書として判定
				dformat = x;
			}
		}

		for(const c of clist) {
			if (c.name && 0 <= line.indexOf(c.name)) name_c = c;
			if (c.tel  && 0 <= line.indexOf(c.tel))  tel_c  = c;
			for(const k of c.keywords)
				if (k && 0 <= line.indexOf(k)) name_c = c;
			if (c.tnumber && 0<= line_space.indexOf(c.tnumber)) tnumber_c=c;
		}

		// 税率
		if (1) {
			const m = line.match(/税.*?(\d?\d)%/);
			if (m) tax_rate = m[1];
		}

		// 金額抽出
		const found = [];
		for(const w of line_space.split(' ')) {
			const m = w.match(/(\d{1,3}(?:,?\d\d\d)*)円/);
			if (!m) continue;
			found.push( m[1].replaceAll(',', '') );
		}

		if (found.length) {
			if (1) {	// 総額
				const m = line.match(/(?:総額|請求額|総合?計|支払い?金?額|領収金?額)[^\d]*(\d{1,3}(?:,?\d\d\d)*)円/);
				if (m) ptotal = m[1].replace(/,/g, '');
			}
			if (1) {	// 合計額（内税か外税か不明）
				const m = line.match(/(?:合計)[^\d]*(\d{1,3}(?:,?\d\d\d)*)円/);
				if (m) pgoukei = m[1].replace(/,/g, '');
			}
			if (1) {
				const m = line.match(/内消費税額(?:\d+%|[^\d])*(\d{1,3}(?:,\d\d\d)*)円/);
				if (m) intax = m[1].replace(/,/g, '');
			}
			if (found.length==1) {
				const p = found[0];
				const m  = line.match(/(税抜|税込)[^\d]*?\d[\d,]*円/)
					|| line.match(/\d[\d,]*円[^\d]*?(税抜|税込)/);
				if (m) pinfo[p]   = m[1];
				  else pinfo[p] ||= 1;
			}
			for(const p of found)
				pinfo[p] ||=1;
		}
	}

	// フォームに設定
	if (dformat)
		$('#dformat').val(dformat).change();
	if (tax_rate)
		$('#tax_rate').val(tax_rate);

 	if (name_c || tnumber_c || tel_c) {
 		const c = tnumber_c || tel_c || name_c;		// T番号、電話番号を優先

		$('#c_pkey').val(c.pkey);
		const $a = $('#client-link');
		$a.text( c.name );
		$a.attr('href', '<@myself2>client/view?pkey=' + c.pkey);
 	}

	// 日付の処理
	if (ymd_list.length) {
		const $ymd  = $('#ymd');
		const $list = $('#date-list');
		const $ogrp = $('#date-list-optgroup');
		for(const d of ymd_list) {
			$list.val(d);
			if ($list.val() === d) continue;

			// new value
			const $opt = $('<option>').attr('value', d).text(d);
			$ogrp.prepend( $opt );
		}
		$list.show();
	 	$ymd.val(ymd_list[ymd_list.length-1]);
	}

	// 総額を発見済
	if (ptotal) {
		$('#total').val(ptotal).change();
		return;
	}

	// 金額を推定して設定
	const plist = Object.keys(pinfo).sort( (a,b) => a-b );
	if (plist.length) {
		const tax_str  = $('#tax_rate').val();
		const tax_rate = tax_str != '' ? parseInt(tax_str) : 10;

		if (intax && tax_rate) {	// 内税表記が存在する
			const th = Math.ceil((intax+1)*(100+tax_rate) / tax_rate);	// 端数切り捨てを考慮し+1円
			$('#tax').val(intax);

			while(plist.length) {
				const max = plist[plist.length -1];
				if (max<th) break;
				plist.pop();		// しきい値超えの金額情報を捨てる
			}
		}

		const max = pgoukei || plist.pop();
		const sub = Math[0<max ? 'ceil' : 'floor'](max*100 / (100 + tax_rate));
		const tax = Math.trunc(sub * tax_rate / 100);

		if (intax && intax==tax							
		 || pinfo[tax] && pinfo[sub] && (pinfo[sub]==1 || pinfo[sub]=='税別')	// 税額と税別額が存在する
		)
		        $('#total').val(max).change();
		else {
			const df = $('#dformat').val();
			for(const x of dformatIntaxList) {	// 請求書、領収書の場合、総額表示が存在するはず
				if (x == df) {
				        $('#total').val(max).change();
					return;
				}
			}
		        $('#subtotal').val(max).change();
		}
	}
});

//------------------------------------------------------------------------------
//●選択されたファイルのハッシュ値を計算し、重複を確認する。
//------------------------------------------------------------------------------
$files.on('change', 'input.doc-file', async function(evt){
	const file = evt.target.files[0];
	if (!file) return;

	const data = await asys.asyncFileReader('readAsArrayBuffer', file);

	let _b64;
	if (crypto.subtle) {
		const sha = await crypto.subtle.digest('SHA-256', data);
		_b64 = btoa( String.fromCharCode.apply(null, new Uint8Array(sha)) );
	} else {
		const hash = sha256.create();
		hash.update( data );
		_b64 = btoa( String.fromCharCode.apply(null, hash.array()) );
	}
	const b64 = b64urlsafe(_b64);

	const $td  = $(evt.target).closest('td');
	$td.find('.doc-filename').attr('title', b64);

	const ret = await asys.send_ajax({
		data: {
			action:	'_ajax_check_document_hash',
			hash:	b64,
			pkey:	$files.data('pkey')
		}
	});
	if (ret.ret != 0) return;	// error

	const $div = $td.find('.file-duplicate');
	const list = ret.list;
	if (!list) {			// not found same hash
		$div.hide();
		return;
	}

	//------------------------------------------------------------
	// ファイル重複警告を表示する
	//------------------------------------------------------------
	const $span = $div.find('.file-duplicate-list').empty();
	const url   = $files.data('viewbase');
	for(const key of list) {
		const $a = $('<a>').attr('href', url + key).text(key);
		$span.append($a);
	}
	$div.show();
});

function b64urlsafe(inp) {
		return inp.replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

//##############################################################################
//●フォームデータ生成
//##############################################################################
const $mainForm = $('#documents-form-table').closest('form');

$mainForm.data('generator', function($form){
	$form.attr('method',  'POST');
	$form.attr('enctype', 'multipart/form-data');

	const fd = new FormData($form[0]);

	const $imgs = $files.find('img.camera-thumbnail');
	for(const img of $imgs) {
		const $img = $(img);
		const blob = $img.data('blob');
		if (!blob) continue;

		fd.append('images_ary', blob, 'camera_iamge.jpg');
	}

	return fd;
});

//##############################################################################
//■カメラ機能
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●シャッターサウンド
////////////////////////////////////////////////////////////////////////////////
const shutterSound = {
	sound: null,
	load: function(url = shutterSoundURL) {
		if (this.sound) return;
		this.sound = new Audio();
		this.sound.preload = 'auto';
		this.sound.src     = url;
	},
	play: function() {
		this.sound.load();
		this.sound.play();
	}
}

////////////////////////////////////////////////////////////////////////////////
//●カメラメイン
////////////////////////////////////////////////////////////////////////////////
const camera = {
	cam: null,
	snapDelay: 1000,	// msec
	width: 1600,
	height: 1200,
	$viewbox: $('#camera-view-box'),

	start: async function(canvas) {
		this.cam = new myCamera(canvas, { width: this.width, height: this.height });
		await this.cam.init();
		this.cam.play();
		this.$viewbox.showDelay();
	},
	stop: function() {
		if (this.cam) this.cam.stop();
		this.cam = null;
		this.$viewbox.hideDelay();
	},
	pause: function() {
		if (!this.cam) return;
		this.cam.stop();
	},
	resume: function() {
		if (!this.cam) return;
		this.cam.play(this.snapDelay);
	},
	changeSize: function(width, height) {
		this.width  = width;
		this.height = height;
		if (!this.cam) return;
		this.cam.changeSize(width, height);
	}
}
const $canvas = $('#camera-view');

$files.on('change', 'input.enableCamera', async function() {
	const $inp = $(this);
	let flag = $inp.prop('checked');
	$inp.addClass('js-fix');

	if (flag) {
		try {
			await camera.start($canvas[0]);
			shutterSound.load();
		} catch (e) {
			console.error(e);
			flag = false;
			$inp.prop('checked', false)
			asys.show_error('カメラの起動に失敗しました。');
		}
	} else {
		camera.stop();
	}

	$inp.removeClass('js-fix');
	$upload.find('input.enableCamera').prop('checked', flag).change();
});
$files.find('tr.last-upload input.enableCamera').change();

$files.on('change', 'select.camera-view-size', function() {
	const val = $(this).val();
	const [width, height] = val.split(',');
	camera.changeSize(width, height);

	$upload.find('select.camera-view-size').val(val).change();
});
$files.find('tr.last-upload select.camera-view-size').change();

////////////////////////////////////////////////////////////////////////////////
//●カメラ撮影
////////////////////////////////////////////////////////////////////////////////
$canvas.on('click', function() {
	camera.pause();

	shutterSound.play();

	const dataUrl = $canvas[0].toDataURL('image/jpeg', 0.9 );
	const $tr     = $('tr.last-upload');
	const $img    = $tr.find('img.camera-thumbnail');
	$img.attr('src', dataUrl);
	$img.show();
	$img.change();

	$canvas[0].toBlob( blog => { $img.data('blob', blog); }, 'image/jpeg', 0.9 );

	view_camera_img(dataUrl);

	camera.resume();
});

//##############################################################################
//■金額計算処理
//##############################################################################
(function(){
	const $subtotal = $('#subtotal');
	const $tax_rate = $('#tax_rate');
	const $tax      = $('#tax');
	const $total    = $('#total');
	const $paid     = $('#paid');
	const $remain   = $('#remain');

	function get_vals() {
		return {
			subtotal: parseInt($subtotal.val().replaceAll(',','')) || 0,
			tax_rate: parseInt($tax_rate.val().replaceAll(',','')) || 0,
			tax	: parseInt($tax     .val().replaceAll(',','')) || 0,
			total	: parseInt($total   .val().replaceAll(',','')) || 0,
			paid	: parseInt($paid    .val().replaceAll(',','')) || 0,
			remain	: parseInt($remain  .val().replaceAll(',','')) || 0
		}
	}
	function set_vals(v) {
		$subtotal.val( asys.printc(v.subtotal) );
		$tax     .val( asys.printc(v.tax)    );
		$total   .val( asys.printc(v.total)  );
		$paid    .val( asys.printc(v.paid)   );
		$remain  .val( asys.printc(v.remain) );

		if (v.subtotal + v.tax == v.total)
			$('#tax-warning').hide();
		else
			$('#tax-warning').show();
	}
	set_vals( get_vals() );

	$subtotal.on('change keyup', evt => {
		if (evt.key == 'Tab') return;	// TAB

		const v  = get_vals();	
		v.tax    = Math.trunc(v.subtotal * v.tax_rate / 100);
		v.total  = v.subtotal + v.tax;
		v.remain = v.total - v.paid;
		set_vals(v);
	});
	$tax_rate.on('change keyup', evt => {
		if (evt.key == 'Tab') return;	// TAB
		$subtotal.change();
	});
	$tax.on('change keyup', evt => {
		if (evt.key == 'Tab') return;	// TAB

		const v  = get_vals();
		v.total  = v.subtotal + v.tax;
		v.remain = v.total - v.paid;
		set_vals(v);
	});
	$total.on('change keyup', evt => {
		if (evt.key == 'Tab') return;	// TAB

		const v   = get_vals();
		v.subtotal= Math[0<v.total ? 'ceil' : 'floor']( v.total*100 / (100 + v.tax_rate) );	// 端数切り上げ
		v.tax     = Math.trunc(v.subtotal * v.tax_rate / 100);
		v.remain  = v.total - v.paid;
		set_vals(v);
	});
	$paid.on('change keyup', evt => {
		if (evt.key == 'Tab') return;	// TAB

		const v  = get_vals();
		v.remain = v.total - v.paid;
		set_vals(v);
	});
	$('#pay-all').on('click', evt => {
		const v = get_vals();
		v.paid  = v.total;
		v.remain= 0;
		set_vals(v);
	});
})();
