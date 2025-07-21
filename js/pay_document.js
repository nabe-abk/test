//##############################################################################
// pay - 売掛・買掛の処理
//
//##############################################################################
//[TAB=8]
'use strict';

const $lines        = $('#pay-lines');		// tbody
const $total_pay    = $('#view-total-paid');
const $total_remain = $('#view-total-remain');

//------------------------------------------------------------------------------
// 全額ボタン
//------------------------------------------------------------------------------
$lines.on('click', 'button.pay-all', evt => {
	const $tr   = $(evt.target).closest('tr');
	const $paid = $tr.find('input.line-paid');
	$paid.val( $tr.data('total') ).change();
});

//------------------------------------------------------------------------------
// 残高と総額の再計算
//------------------------------------------------------------------------------
function recalc_total() {
	let total_paid  =0;
	let total_remain=0;

	for(const dom of $lines.children('tr')) {
		const $tr = $(dom);
		const $paid   = $tr.find('input.line-paid');
		const $remain = $tr.find('td.line-remain');
		const paid    = asys.get_price($paid.val());
		const remain  = $tr.data('total') - paid;
		$remain.text(asys.printc(remain));	

		total_paid   += paid;
		total_remain += remain;
	}
	$total_pay   .text(asys.printc(total_paid));
	$total_remain.text(asys.printc(total_remain));
}

$lines.on('change keyup', 'input.line-paid', recalc_total);

// init
recalc_total()

//##############################################################################
//■カーソル処理
//##############################################################################
let Cols;	// カラム数
const InputSelector = 'input:not([type="hidden"]), button';

function init_cursol() {
	const $line = $lines.find('tr:first-child');
	if (!$line.length) return;

	Cols = $line.find(InputSelector).length;
	$lines.on('keydown',  InputSelector, cursol_move);
}
init_cursol();

////////////////////////////////////////////////////////////////////////////////
//●カーソル移動
////////////////////////////////////////////////////////////////////////////////
function cursol_move(evt) {
	const key  = evt.keyCode;
	const $inp = $(evt.target);

	if (key == 27) {	// ESC
		$inp.removeClass('edit');
		if ($inp.data('bak') !== undefined) {
			$inp.val( $inp.data('bak') );
			$inp.removeData('bak');
		}
	}
	if (key == 13) {	// enter
		if ($inp[0].tagName == 'BUTTON')
			return $inp.click();

		$inp.removeClass('edit');
		if (($inp.attr('type') == 'date' || $inp.hasClass('date') || $inp.hasClass('months')) && $inp.val() == '') {
			const uptd = cursol_up_down(evt, -1, true);
			if (uptd) $inp.val( $(uptd).val() ).change();	// copy from up
		}
		if (!cursol_left_right(evt, 1)) {
			$inp.data('by_enter', true);
			$inp.change();	// right
			$inp.data('by_enter', false);
		}
	}

	if (key == 38) return cursol_up_down(evt, -1);		// up
	if (key == 40) return cursol_up_down(evt,  1);		// down

	const edit = $inp.hasClass('edit') && $inp.val() != '';
	if (edit) return;

	if (key ==  37) return cursol_left_right(evt, -1);	// left
	if (key ==  39) return cursol_left_right(evt,  1);	// right
	if (key == 113)	return rinput_into_edit($inp);		// F2

	if (!$inp.prop('readonly') && $inp.attr('name') != 'title') {
		if (key ==  46)	return $inp.val('');		// delete
		if (key ==   8)	return $inp.val('');		// backspace
	}
}

function cursol_up_down(evt, df, no_focus) {
	const $inp = $(evt.target);
	const $tr  = $inp.closest('tr');
	const $tr2 = (df==1 ? $tr.next('tr') : $tr.prev('tr'));

	evt.preventDefault();
	if (!$tr2.length) return;		// 最初の行か最後の行

	const idx = get_index($tr, $inp);
	const target = $tr2.find(InputSelector)[idx];
	if (!no_focus && target) $(target).focus();
	if (target && $(target).prop('disabled')) {
		evt.target = target;
		return cursol_up_down(evt, df, no_focus);
	}
	return target;
}

function cursol_left_right(evt, df) {
	const $inp = $(evt.target);
	const $tr  = $inp.closest('tr');
	let   idx  = get_index($tr, $inp) + df;

	evt.preventDefault();
	if (idx<0 || Cols<=idx) return;	// 端

	const $cols = $tr.find(InputSelector);

	let target = $cols[idx];	// skip disabled
	while(0<idx && idx<Cols && (target.disabled || target.readOnly)) {
		idx = idx + df;
		target  = $cols[idx];
	}
	if (target) $(target).focus();
	return target;
}

////////////////////////////////////////////////////////////////////////////////
//●入力部のフォーカスと編集モード
////////////////////////////////////////////////////////////////////////////////
$lines.on('focus',    InputSelector, rinput_focus);
$lines.on('blur',     InputSelector, rinput_blur);
$lines.on('keypress', InputSelector, rinput_keypress);

function rinput_focus(evt) {
	const $inp = $(evt.target);
	const $td  = $inp.closest('td');
	$inp.data('bak', $inp.val());
}

function rinput_blur(evt) {
	const $inp = $(evt.target);
	const $td  = $inp.closest('td');
	$inp.removeClass('edit');
}

function rinput_keypress(evt) {
	const key = evt.keyCode;
	const $inp = $(evt.target);
	if (key == 13 || $inp.hasClass('edit') || $inp.prop('readonly')) return;

	rinput_into_edit($inp);
	if ($inp.attr('name') != 'title') $inp.val('');
}

function rinput_into_edit($inp) {
	$inp.addClass('edit');
}

////////////////////////////////////////////////////////////////////////////////
//●行内の番号の取得
////////////////////////////////////////////////////////////////////////////////
function get_index($parent, $target) {
	const target = $target[0];
	let num;
	$parent.find(InputSelector).each(function(idx, dom) {
		if (dom == target) num=idx;
	});
	if (num===undefined) throw('get_index(): Not found element', target)
	return num;
}
