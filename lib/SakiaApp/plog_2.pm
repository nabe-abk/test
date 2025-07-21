use strict;
################################################################################
# ■取引先管理
################################################################################
package SakiaApp::plog;
#-------------------------------------------------------------------------------
# ●取引先一覧のロード
#-------------------------------------------------------------------------------
sub load_clients {
	my $self  = shift;
	my $query = shift;
	my $DB    = $self->{DB};

	my %h = (boolean => {});

	# 検索ワード
	my $q = $query->{q};
	$self->normalize_string($q);
	$query->{_q} = $q;
	if ($q ne '') {
		$q =~ s/(東京都|北海道|大阪府|京都府|[\x7f-]*県) */$1 /g;
		$self->make_search_words(\%h, $q);
		$h{search_cols} = [ qw(name kana fullname tnumber pref address1 address2 _tel ch_name ch_email tags) ];
	}

	if ($query->{ctype} eq 'buy') {
		$h{boolean}->{for_buy} = 1;
	}
	if ($query->{ctype} eq 'sale') {
		$h{boolean}->{for_sale} = 1;
	}

	my $timing = int($query->{bi_timing});
	if ($timing) {
		$h{match}->{bi_timing} = $timing;
	}

	my $sort = $query->{sort} || 'kana';
	if ($sort ne 'kana' && $sort ne '-kana') {
		$h{sort} = [ $sort, 'kana' ];
	} else {
		$h{sort} = $sort;
	}

	if ($query->{limit} ne 'all') {
		$h{limit} = int($query->{limit}) || 100;
	}

	return $DB->select('client', \%h);
}

#-------------------------------------------------------------------------------
# ●取引先のロード
#-------------------------------------------------------------------------------
sub load_client {		# cached
	my $self = shift;
	my $pkey = shift;
	my $DB   = $self->{DB};

	my $c = $self->{_load_client_cache};
	my $h = $c->{$pkey} || ($c->{$pkey} = $DB->select_match_limit1('client', 'pkey', $pkey));
	if (!$h) { return; }

	my %x = %$h;	# copy
	return \%x;
}

sub load_client_name {
	my $self = shift;
	return $self->load_client(@_)->{name};
}

#-------------------------------------------------------------------------------
# ●取引先の追加
#-------------------------------------------------------------------------------
sub _ajax_add_client {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ];
	}

	#-------------------------------------------------------------
	# データチェック
	#-------------------------------------------------------------
	my $data = $self->check_client_data($form);
	if (!$data) {
		return [ 10, $ROBJ->form_err() ]
	}

	#-------------------------------------------------------------
	# insert
	#-------------------------------------------------------------
	my $pkey = $DB->insert('client', $data);
	if (!$pkey) {
		return [ 90, '登録に失敗しました。' ];
	}

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	$self->log('client', $pkey, '作成', '新規登録');

	$data->{pkey} = $pkey;
	return { ret=>0, data=>$data };
}

#-------------------------------------------------------------------------------
# ●取引先の編集
#-------------------------------------------------------------------------------
sub _ajax_edit_client {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ]
	}
	my $old = $self->load_client( $form->{pkey} );
	if (!$old) {
		return [ 11, '指定の取引先が見つかりません。' ];
	}
	my $pkey = $old->{pkey};

	#-------------------------------------------------------------
	# データチェック
	#-------------------------------------------------------------
	my $data = $self->check_client_data($form, $old);
	if (!$data) {
		return [ 10, $ROBJ->form_err() ]
	}
	$data->{'*update_tm'} = 'CURRENT_TIMESTAMP';

	#-------------------------------------------------------------
	# 更新処理
	#-------------------------------------------------------------
	$DB->begin();
	$DB->update_match('client', $data, 'pkey', $pkey);

	# 所属データに、継承カラムをコピーする
	$data->{pkey} = $pkey;

	# 取引先コード変更時、契約コードも変更
	if ($data->{ccode} ne $old->{ccode}) {
		$self->update_rcode_by_ccode( $pkey, $data->{ccode} );
	}

	#-------------------------------------------------------------
	# commit
	#-------------------------------------------------------------
	my $r = $DB->commit();
	if ($r) {
		return [ 99, '編集に失敗しました。' ];
	}

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	my $msg = $self->make_client_log_msg($data, $old);
	if ($msg) {
		$self->log('client', $pkey, '編集', $msg);
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●取引先データのチェック
#-------------------------------------------------------------------------------
sub check_client_data {
	my $self = shift;
	my $form = shift;
	my $old  = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};

	$ROBJ->clear_form_err();

	my $name    = $form->{name};
	my $kana    = $form->{kana};
	my $fullname= $form->{fullname};
	my $tnumber = $form->{tnumber};

	my $zip  = $form->{zipcode};
	my $pref = $form->{pref};
	my $adr1 = $form->{address1};
	my $adr2 = $form->{address2};
	my $tel  = $form->{tel};
	my $fax  = $form->{fax};

	my $ch_name  = $form->{ch_name};
	my $ch_email = $form->{ch_email};
	my $ch_tel   = $form->{ch_tel};

	$self->normalize_string($name, $kana, $fullname, $tnumber, $pref, $adr1, $adr2);
	foreach($zip, $tel, $fax, $ch_tel) {
		$_ =~ s/[^\d\-#]//g;
	}

	$name     =~ s/㈱|\(株\)|（株）|株式会社//g;
	$fullname =~ s/㈱|\(株\)|（株）/株式会社/g;
	$kana     =~ s/\s*カブシキ(?:ガ|カ)イシャ\s*//;

	if ($name eq '') {
		$ROBJ->form_err('name', '名称が設定されていません。');
	}
	my @not_match;
	if ($old && $old->{pkey}) {	# 編集時は自分自身を除外
		push(@not_match, '-pkey', $old->{pkey});
	}
	if ($name ne '' && $DB->select_match_pkey1('client', 'name', $name, @not_match)) {
		$ROBJ->form_err('name', '名称が重複しています。');
	}
	if ($tnumber ne '' && $tnumber !~ /^T\d+/) {
		$ROBJ->form_err('tnumber', '登録番号の書式が正しくありません。');
	}

	$ch_email =~ s/\s//g;
	if ($ch_email ne '' && $ch_email !~ /^[\w\.!#\$%&'*+\/=\?^_`\{\|\}~\-]+@[\w\-]+(?:\.[\w\-]+)*$/) {
		$ROBJ->form_err('ch_email', '担当者E-mailが不正です。');
	}

	my $data = {
		name		=> $name,
		kana		=> $kana,
		fullname	=> $fullname,
		tnumber		=> $tnumber,

		for_buy		=> $form->{for_buy}  ? 1 : 0,
		for_sale	=> $form->{for_sale} ? 1 : 0,

		ch_name		=> $ch_name,
		ch_tel		=> $ch_tel,
		ch_email	=> $ch_email,

		zipcode		=> $zip,
		pref		=> $pref,
		address1	=> $adr1,
		address2	=> $adr2,

		tel		=> $tel,
		fax		=> $fax,

		tags		=> $self->normalize_tags( $form->{tags} ),
		keywords	=> $self->normalize_tags( $form->{keywords} ),
		memo		=> $self->normalize_memo( $form->{memo_txt} )
	};
	$self->make_search_tel($data);

	foreach(qw(bi_timing pay_month pay_timing)) {
		my $x = $form->{$_};
		$x =~ s/\s//g;
		if ($x ne '') {
			$x = int($x);
			if ($_ =~ /_timing$/) {
				if ($x<1 || 28<$x) { $x = 31; }
			} else {
				if ($x< 0) { $x = 0; }
				if (12<$x) { $x =12; }
			}
		}
		$data->{$_} = $x;
	}

	if ($ROBJ->form_err()) { return; }

	return $data;
}

sub make_search_tel {
	my $self = shift;
	my $data = shift;
	my $tel='';
	foreach(qw(tel fax zipcode ch_tel)) {
		my $x = $data->{$_};
		$x =~ s/[^\d]//g;
		if ($x ne '') {
			$tel .= "$x ";
		}
	}
	chop($tel);
	if ($tel) { $data->{_tel} = $tel; }
	return $tel;
}

#-------------------------------------------------------------------------------
# ●取引先の削除
#-------------------------------------------------------------------------------
sub _ajax_delete_client {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ]
	}

	my $h    = $self->load_client( $form->{pkey} );
	my $pkey = $h->{pkey};

	if (!$h) {
		return [ 11, '対象の取引先が見つかりません。' ];
	}
	if ($h->{use_cnt}) {
		return [ 12, '使用されているため、削除できません。' ];
	}

	my $r = $DB->delete_match('client', 'pkey', $pkey);
	if ($r != 1) {
		return [ 90, '削除に失敗しました' ];
	}

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	my $msg = $self->make_client_log_msg($h);
	$self->log('client', $pkey, '削除', $msg);

	return 0;
}

#-------------------------------------------------------------------------------
# ●取引先ログの生成
#-------------------------------------------------------------------------------
sub make_client_log_msg {
	my $self = shift;
	my $new  = shift;
	my $old  = shift;
	return $self->make_log_msg($new, $old, {
		name		=> '名称',
		kana		=> 'フリガナ',
		fullname	=> '正式名',
		tnumber		=> '登録番号',

		for_buy		=> '購入先',
		for_sale	=> '販売先',

		zipcode		=> '郵便番号',
		pref		=> '都道府県',
		address1	=> '住所1',
		address2	=> '住所2',
		tel		=> '電話番号',
		fax		=> 'FAX番号',

		ch_name		=> '担当者名',
		ch_email	=> '担当者Email',
		ch_tel		=> '担当者TEL',

		bi_timing	=> '締日',
		pay_month	=> '支払月',
		pay_timing	=> '支払日',

		tags 		=> 'タグ',
		keywords	=> 'キーワード'
	},{
		# ignore
		_tel		=> 1
	},{
		for_buy		=> 'flag',
		for_sale	=> 'flag'
	});
}

#-------------------------------------------------------------------------------
# ●取引先の使用状況更新
#-------------------------------------------------------------------------------
sub update_client_use_info {
	my $self = shift;
	my $pkey = shift;
	my $DB   = $self->{DB};

	my $h = $DB->select_match_limit1('document', 'c_pkey', $pkey,
		 '*cols', ['count(pkey) _count', 'max(ymd) _ymd']
	);

	my $data = {
		use_cnt 	=> $h ? $h->{_count} : 0,
		lastuse_ymd	=> $h ? $h->{_ymd}   : undef
	};
	$DB->update_match('client', $data, 'pkey', $pkey);
}

1;
