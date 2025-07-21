use strict;
################################################################################
# user
################################################################################
package SakiaApp::plog;
################################################################################
# ■DB初期化
################################################################################
sub db__init {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $r1 = $DB->create_table_wrapper('client', <<INFO);
		pkey		serial PRIMARY KEY	# 変更不可

		name		text UNIQUE NOT NULL	# 名称
		kana		text 			# フリガナ
		fullname	text 			# 正式名
		tnumber		text			# 税務登録番号

		for_buy		boolean NOT NULL	# 購入先
		for_sale	boolean NOT NULL 	# 販売先

		zipcode		text			# 郵便番号
		pref		text			# 都道府県
		address1	text			# 住所1
		address2	text			# 住所2
		tel		text			# 電話番号
		fax		text			# FAX番号
		_tel		text			# 検索用（ハイフンなし）

		ch_name		text			# 担当者
		ch_email	text			# 担当者メールアドレス
		ch_tel		text			# 担当者電話番号

		bi_timing	int			# 締日
		pay_month	int			# ◯ヶ月後
		pay_timing	int			# ◯日払

		tags		text			# タグ
		keywords	text			# 会社自動判定用のキーワード
		memo		ltext			# メモ

		create_tm	TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP	# 作成日時
		update_tm	TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP	# 更新日時

		use_cnt		int NOT NULL DEFAULT 0
		lastuse_ymd	DATE

		INDEX		for_buy
		INDEX		for_sale
		INDEX		name
		INDEX		kana
		INDEX		tags
		INDEX		create_tm
		INDEX		update_tm
		INDEX		lastuse_ymd

		INDEX_TDB	_tel, fullname, ch_name, ch_email
		INDEX_TDB	pref, address1, address2, tnumber, bi_timing
		INDEX_TDB	keywords
INFO

	my $r2 = $DB->create_table_wrapper('document', <<INFO);
		pkey		serial PRIMARY KEY

		ymd		date NOT NULL			# 書類日付（YYYYMMDD）
		dtype		text NOT NULL			# 種別
		dformat		text NOT NULL			# 書式（請求, 見積, 発注...）
		dcode		text				# 書類code

		c_pkey		int  NOT NULL ref(client.pkey)	# 相手先
		title		text				# 概要

		subtotal	int NOT NULL			# 税抜額
		tax_rate	int NOT NULL			# 税率(%単位)
		tax		int NOT NULL			# 税額
		total		int NOT NULL			# 総額
		paid_ymd	DATE				# 決済日（YYYYMMDD）
		paid		int				# 決済額
		remain		int				# 残高（未決済額）

		files		text NOT NULL			# ファイル名。TAB区切り
		memo		ltext				# メモ

		create_tm	TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP	# 作成日時
		update_tm	TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP	# 更新日時

		INDEX		ymd
		INDEX		dtype
		INDEX		dformat
		INDEX		dcode

		INDEX		c_pkey
		INDEX		subtotal
		INDEX		tax
		INDEX		total
		INDEX		remain
		INDEX		create_tm
		INDEX		update_tm
		INDEX		paid_ymd

		INDEX_TDB	title, tax_rate, paid
INFO

	my $r3 = $DB->create_table_wrapper('log', <<INFO);
		pkey		serial PRIMARY KEY
		u_pkey		int ref(usr.pkey)	# 操作者pkey / システムの場合NULL

		tbl		text NOT NULL		# テーブル名
		tbl_pkey	int			# テーブル主キー
		type		text NOT NULL		# 操作タイプ ex)create, edit, delete
		msg		text			# 操作内容

		ip		text						# IPアドレス
		host		text						# HOST
		tm		TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP	# 作成日時

		INDEX		tbl
		INDEX		tbl_pkey
		INDEX		u_pkey
		INDEX		type
		INDEX		tm
INFO

	my $ret = $r1 + $r2 + $r3;
	if ($ret) {
		$r3 || $DB->drop_table('log');
		$r2 || $DB->drop_table('paper');
		$r1 || $DB->drop_table('client');
	}
	return $ret;	# 0 = 成功
}

1;
