use strict;
################################################################################
# ■取引管理
################################################################################
package SakiaApp::plog;
#-------------------------------------------------------------------------------
# ●書類一覧のロード
#-------------------------------------------------------------------------------
sub load_documents {
	my $self  = shift;
	my $query = shift;
	my $DB    = $self->{DB};

	my %h = (
		cols	=> ['d.*', 'c.name', 'c.kana'],
		match	=> {},
		boolean => {},
		ljoin => {
			table	=> 'client c',
			left	=> 'd.c_pkey',
			right	=> 'c.pkey'
		}
	);

	# 検索ワード
	my $q = $query->{q};
	$self->normalize_string($q);
	$query->{_q} = $q;
	if ($q ne '') {
		$q =~ s/(東京都|北海道|大阪府|京都府|[\x7f-]*県) */$1 /g;
		$self->make_search_words(\%h, $q);
		$h{search_cols} = [ qw(c.name c.kana dcode title) ];
	}

	my $dtype   = $query->{dtype};
	my $dformat = $query->{dformat};
	if ($self->{dtypes}->{$dtype}) {
		$h{match}->{dtype} = $dtype;
	}
	if ($self->{dformats}->{$dformat}) {
		$h{match}->{dformat} = $dformat;
	}

	# 取引先指定
	my $c_pkey = int($query->{c_pkey});
	if ($c_pkey) {
		$h{match}->{c_pkey} = $c_pkey;
	}

	# 年月指定
	my $year = int($query->{year});
	my $mon  = int($query->{mon});
	if ($year) {
		if ($mon) {
			$h{min}->{ymd} = "$year-$mon-01";
			$mon++; if (12<$mon) { $year++; $mon=1; }
			$h{lt}->{ymd}  = "$year-$mon-01"
		} else {
			$h{min}->{ymd} = "$year-01-01";
			$h{max}->{ymd} = "$year-12-31";
		}
	}

	# date指定
	my $from = $self->normalize_date($query->{from_date});
	my $to   = $self->normalize_date($query->{to_date});
	if ($from) {
		$h{min}->{ymd} = $from;
	}
	if ($to) {
		$h{max}->{ymd} = $to;
	}

	# 金額
	my $ptype = $query->{price_type};
	my $min   = $query->{min_price};
	my $max   = $query->{max_price};
	if ($min ne '') {
		$h{min}->{$ptype} = int($min);
	}
	if ($max ne '') {
		$h{max}->{$ptype} = int($max);
	}

	# 残高あり
	if ($query->{remain}) {
		$h{min}->{remain} = 1;
	}

	my $sort = $query->{sort} || 'ymd';
	$sort = $sort =~ /^(-)?(\w+_tm)$/ ? "${1}d.$2" : $sort;
	if ($sort =~ /ymd$/) {
		my $pkey = substr($sort,0,1) eq '-' ? '-d.pkey' : 'd.pkey';
		$h{sort} = [ $sort, $pkey ];
	} else {
		$h{sort} = [ $sort, 'ymd', 'd.pkey' ];
	}

	if ($query->{limit} ne 'all') {
		$h{limit} = int($query->{limit}) || 100;
	}

	return $DB->select('document d', \%h);
}

#-------------------------------------------------------------------------------
# ●書類のロード
#-------------------------------------------------------------------------------
sub load_document {
	my $self = shift;
	my $pkey = shift;
	my $DB   = $self->{DB};

	return $DB->select_match_limit1('document', 'pkey', $pkey);
}

sub load_document_files {
	my $self = shift;
	my $h    = shift;
	return [ split(/\t/, $h->{files}) ];
}

sub get_file_ext {
	my $self = shift;
	return shift =~ /\.(\w+)$/ ? $1 =~ tr/a-z/A-Z/r : 'unknown';
}

#-------------------------------------------------------------------------------
# ●書類の追加
#-------------------------------------------------------------------------------
sub _ajax_add_document {
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
	my ($data, $new_files) = $self->check_document_data($form);
	if (!$data) {
		return [ 10, $ROBJ->form_err() ]
	}

	#-------------------------------------------------------------
	# insert
	#-------------------------------------------------------------
	my $pkey = $DB->insert('document', $data);
	if (!$pkey) {
		$self->delete_document_files($pkey, $new_files);
		return [ 90, '登録に失敗しました。' ];
	}

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	my $msg = $self->make_document_log_msg({ files => $data->{files} });
	$self->log('document', $pkey, '作成', "新規登録\n" . $msg);

	#-------------------------------------------------------------
	# 取引先使用状況更新
	#-------------------------------------------------------------
	$self->update_client_use_info($data->{c_pkey});

	#-------------------------------------------------------------
	# return data
	#-------------------------------------------------------------
	$data->{pkey} = $pkey;
	return { ret=>0, data=>$data };
}

#-------------------------------------------------------------------------------
# ●書類の編集
#-------------------------------------------------------------------------------
sub _ajax_edit_document {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ];
	}

	my $pkey = int($form->{pkey});
	my $old  = $DB->select_match_limit1('document', 'pkey', $pkey);
	if (!$old) {
		return [ 2, '編集対象のデータが見つかりません。' ];
	}

	#-------------------------------------------------------------
	# データチェック
	#-------------------------------------------------------------
	my ($data, $new_files, $ren_files, $del_files) = $self->check_document_data($form, $old);
	if (!$data) {
		return [ 10, $ROBJ->form_err() ]
	}
	$data->{'*update_tm'} = 'CURRENT_TIMESTAMP';

	#-------------------------------------------------------------
	# insert
	#-------------------------------------------------------------
	my $r = $DB->update_match('document', $data, 'pkey', $pkey);
	if ($r != 1) {
		$self->delete_document_files($pkey, $new_files);
		return [ 90, '編集に失敗しました。' ];
	}

	#-------------------------------------------------------------
	# 添付書類の処理
	#-------------------------------------------------------------
	my $dir = $self->{pub_dir};
	foreach(keys(%$ren_files)) {
		rename("$dir$_", $dir . $ren_files->{$_});
	}
	$self->delete_document_files($pkey, $del_files);

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	my $msg = $self->make_document_log_msg($data, $old);
	if ($msg) {
		$self->log('document', $pkey, '編集', $msg);
	}

	#-------------------------------------------------------------
	# 取引先使用状況更新
	#-------------------------------------------------------------
	$self->update_client_use_info($old->{c_pkey});

	return 0;
}

#-------------------------------------------------------------------------------
# ●書類データのチェック
#-------------------------------------------------------------------------------
sub check_document_data {
	my $self = shift;
	my $form = shift;
	my $old  = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};

	$ROBJ->clear_form_err();

	#---------------------------------------------------
	# 金額以外
	#---------------------------------------------------
	my $ymd     = $self->normalize_date($form->{ymd});
	my $dtype   = $form->{dtype};
	my $dformat = $form->{dformat};
	my $dcode   = $self->normalize_string($form->{dcode});
	my $title   = $self->normalize_string($form->{title});

	if ($ymd eq '') {
		$ROBJ->form_err('ymd', '日付が正しくありません。');
	}

	if ($dtype eq '') {
		$ROBJ->form_err('dtype', '種別を選択してください。');
	} elsif ($dtype eq '_order' || !$self->{dtypes}->{$dtype}) {
		$ROBJ->form_err('dtype', '種別が正しくありません。');
	}

	if ($dformat eq '') {
		$ROBJ->form_err('dformat', '書式を選択してください。');
	} elsif ($dformat eq '_order' || !$self->{dformats}->{$dformat}) {
		$ROBJ->form_err('dformat', '書式が正しくありません。');
	}

	my $c_pkey = int($form->{c_pkey});
	if (!$c_pkey) {
		$ROBJ->form_err('c_pkey', '相手先を選択してください。');
	} elsif (!$DB->select_match_pkey1('client', 'pkey', $c_pkey)) {
		$ROBJ->form_err('c_pkey', '相手先が見つかりません。');
	}

	#---------------------------------------------------
	# 金額とか
	#---------------------------------------------------
	my $subtotal = int($form->{subtotal} =~ s/,//gr);
	my $tax_rate = int($form->{tax_rate});
	my $tax      = int($form->{tax}      =~ s/,//gr);
	my $total    = int($form->{total}    =~ s/,//gr);

	if (0<=$subtotal && $tax<0) {
		$ROBJ->form_err('tax', '税額が負になっています。');
	}
	if ($subtotal + $tax != $total) {
		$ROBJ->form_err('total', '総額が正しくありません。');
	}

	#-------------------------------------------------------------
	# create row data
	#-------------------------------------------------------------
	my $data = {
		ymd	=> $ymd,
		dtype	=> $dtype,
		dformat	=> $dformat,
		dcode	=> $dcode,

		c_pkey	=> $c_pkey,
		title	=> $title,

		subtotal=> $subtotal,
		tax_rate=> $tax_rate,
		tax	=> $tax,
		total	=> $total,

		memo	=> $self->normalize_memo( $form->{memo_txt} )
	};

	#---------------------------------------------------
	# 決済情報
	#---------------------------------------------------
	$data->{paid_ymd} = $form->{paid_ymd};
	$data->{paid}     = $form->{paid};

	if ($dformat eq $self->{dformat_invoice}) {
		$self->check_paid_data('paid_ymd', 'paid', $data);
	} else {
		$data->{paid_ymd} = undef;
		$data->{paid}     = undef;
		$data->{remain}   = undef;
	}

	#-------------------------------------------------------------
	# pkey生成
	#-------------------------------------------------------------
	if ($ROBJ->form_err()) {
		return;
	}

	my $pkey = $old && $old->{pkey};
	if (!$old) {
		$pkey = $DB->generate_pkey('document');
		if (!$pkey) {
			$ROBJ->form_err(undef, 'データベースへの登録に失敗しました。');
		}
		$data->{pkey} = $pkey;
	}

	#-------------------------------------------------------------
	# 添付書類
	#-------------------------------------------------------------
	my %saved = $old && (map {$_ => 1} split(/\t/, $old->{files}));
	my %shalist;

	my $ary  = $form->{files_ary};
	my $imgs = $form->{images_ary} || [];	# camera images
	my @files;
	my @new_files;
	my %rename_files;
	foreach(@$ary) {
		if (@$imgs && ref($_) && $_->{'name'} eq '') { $_ = shift(@$imgs); }
		if (!ref($_)) {
			if (!$saved{$_}) {
				$ROBJ->form_err("files_ary#$_", '既存ファイルが消えています。編集画面をリロードしてください。');
				next;
			}
			delete $saved{$_};

			my $sha  = $self->get_sha256_from_filename($_);
			my $name = $self->format_filename($pkey, $data, $_, $sha);
			if ($name ne $_) {
				$rename_files{$_} = $name;
			}
			$shalist{$sha} = 1;
			push(@files, $name);
			next;
		}
		#
		# form files
		#
		if ($_->{name} eq '') { next; }
		if (!$_->{size}) {
			$ROBJ->form_err("files_ary#$_", 'ファイルサイズが 0 です: %s', $_->{name});
			next;
		}

		my $sha  = $self->get_sha256_b64url($_);
		my $name = $self->format_filename($pkey, $data, $_->{name}, $sha);
		if (!$name) {
			$ROBJ->form_err("files_ary#$_", 'このファイルは登録できません: %s', $_->{name});
			next;
		}
		if ($shalist{$sha}) {
			$ROBJ->form_err("files_ary#$shalist{$sha}");
			$ROBJ->form_err("files_ary#$_", '同じ内容のファイル（または画像）が複数指定されています: %s', $_->{name});
			next;
		}
		$shalist{$sha}=$_;

		#
		# save file
		#
		if ($self->save_form_file($_, $name)) {
			$ROBJ->form_err("files_ary#$_", 'ファイルの保存に失敗しました: %s', $name);
			next;
		}
		$self->append_to_hash_data_file($pkey, $sha);

		push(@files,     $name);
		push(@new_files, $name);
	}
	if (!@files) {
		$ROBJ->form_err("files_ary", 'ファイルが指定されていません。');
	}
	my @del_files  = keys(%saved);
	$data->{files} = join("\t", @files);


	if ($ROBJ->form_err()) {
		$self->delete_document_files($pkey, \@new_files);
		return;
	}

	return ($data, \@new_files, \%rename_files, \@del_files);
}

sub check_paid_data {
	my $self = shift;
	my $err_date = shift;
	my $err_paid = shift;
	my $data = shift;
	my $ROBJ = $self->{ROBJ};

	my $date = $data->{paid_ymd};
	my $paid = $data->{paid};
	$date = $self->normalize_date($date);
	$paid = int($paid =~ s/[^-\d]//gr);

	# not pay
	if (!$paid) {
		$data->{paid_ymd} = undef;
		$data->{paid}     = 0;
		$data->{remain}   = $data->{total};
		return $data;
	}

	if (!$date) {
		$ROBJ->form_err($err_date, "日付が正しくありません: %s", $data->{paid_ymd});
		return;
	}
	if ($paid < 0) {
		$ROBJ->form_err($err_paid, "入金額が負になっています: %d", $data->{paid});
		return;
	}
	if ($data->{total} < $paid) {
		$ROBJ->form_err($err_paid, "入金額が総額を超えています: %d", $data->{paid});
		return;
	}

	# save
	$data->{paid_ymd} = $paid ? $date : undef;
	$data->{paid}     = $paid;
	$data->{remain}   = $data->{total} - $paid;
	return	$data;
}


#-------------------------------------------------------------------------------
# ●書類の削除
#-------------------------------------------------------------------------------
sub _ajax_delete_document {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ]
	}

	my $h    = $self->load_document( $form->{pkey} );
	my $pkey = $h->{pkey};

	if (!$h) {
		return [ 11, '対象の書類が見つかりません。' ];
	}
	my $r = $DB->delete_match('document', 'pkey', $pkey);
	if ($r != 1) {
		return [ 90, '削除に失敗しました' ];
	}

	#-------------------------------------------------------------
	# ファイル削除
	#-------------------------------------------------------------
	my @files = split(/\t/, $h->{files});
	$self->delete_document_files($pkey, \@files);

	#-------------------------------------------------------------
	# ログ記録
	#-------------------------------------------------------------
	my $msg = $self->make_document_log_msg($h);
	$self->log('document', $pkey, '削除', $msg);

	#-------------------------------------------------------------
	# 取引先使用状況更新
	#-------------------------------------------------------------
	$self->update_client_use_info($h->{c_pkey});

	return 0;
}

################################################################################
# ■入金処理（売掛・買掛）
################################################################################
sub _ajax_save_pay {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ]
	}

	my $pkeys = $form->{pkey_ary};
	my $dates = $form->{date_ary};
	my $pays  = $form->{paid_ary};

	foreach(0..$#$pkeys) {
		my $pkey = $pkeys->[$_];
		my $date = $dates->[$_];
		my $paid = $pays->[$_];
		my $h    = $self->load_document($pkey);
		if (!$h) {
			$ROBJ->form_err("pkey_ary#$_", "対象の書類が見つかりません: %d", $pkey);
			next;
		}
		if ($h->{dformat} ne $self->{dformat_invoice}) {
			$ROBJ->form_err("pkey_ary#$_", "対象の形式が「%s」ではありません: %s", $self->{dformat_invoice}, $h->{dformat});
			next;
		}
		if ($date ne '' || $paid ne '') {
			my $data = $self->check_paid_data("date_ary#$_", "pkey_ary#$_", {
				total	=> $h->{total},
				paid_ymd=> $date,
				paid	=> $paid
			});
			if (!$data) { next; }
			$date = $data->{paid_ymd};
			$paid = $data->{paid};
		}
		if ($paid eq $h->{paid} && $date eq $h->{paid_ymd}) {
			next;	# skip
		}

		#-------------------------------------------------------------
		# 入金処理
		#-------------------------------------------------------------
		my $data = {
			paid_ymd	=> $date,
			paid		=> $paid,
			remain		=> $h->{total} - $paid,
			'*update_tm'	=> 'CURRENT_TIMESTAMP'
		};
		my $r = $DB->update_match('document', $data, 'pkey', $pkey);
		if ($r != 1) {
			$ROBJ->form_err("paid_ary#$_", "入金に失敗しました: %d", $pkey);
			next;
		}

		#-------------------------------------------------------------
		# ログ記録
		#-------------------------------------------------------------
		my $msg = $self->make_document_log_msg($data, $h);
		$self->log('document', $pkey, '入金', $msg);
	}

	if ($ROBJ->form_err()) {
		return [ 90, $ROBJ->form_err() ];
	}

	return 0;
}

################################################################################
# ■書類関連のサービスルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●書類の重複確認
#-------------------------------------------------------------------------------
sub _ajax_check_document_hash {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ];
	}

	my $pkey = int($form->{pkey});
	my $hash = $form->{hash};
	if ($hash =~ /[^\w\-]/) {
		return [ 10, 'ハッシュのフォーマットがBase64 URLではありません。' ];
	}

	my $file = $self->get_hash_data_file($hash);
	if (!-r $file) {
		return 0;	# sucess
	}

	my $lines = $ROBJ->fread_lines($file);
	my @ary   = grep { $_ && $_ != $pkey } map { int($_) } @$lines;
	if (!@ary) {
		return 0;	# sucess
	}

	return { ret=>0, list=>\@ary };
}
#-------------------------------------------------------------------------------
# ●書類の改ざんチェック
#-------------------------------------------------------------------------------
sub _ajax_tamper_check {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{ok}) {
		return [ 1, $ROBJ->translate('Operation not permitted.') ];
	}

	my $h = $self->load_document($form->{pkey});
	if (!$h) {
		return [ 10, '書類データが見つかりません。' ];
	}
	my $files = $self->load_document_files($h);
	my $dir   = $self->{pub_dir};

	my %list;
	foreach(@$files) {
		my $sha0 = $self->get_sha256_b64url( $dir . $_ );
		my $sha1 = $self->get_sha256_from_filename( $_ );

		$list{$_} = $sha0 eq $sha1 ? 1 : 0;
	}
	return { ret=>0, list=>\%list };
}

#-------------------------------------------------------------------------------
# ●取引先データのロード
#-------------------------------------------------------------------------------
sub load_clients_for_match {
	my $self = shift;
	my $DB   = $self->{DB};

	return $DB->select_match('client', '*cols', ['pkey', 'name', 'tnumber', 'tel', 'keywords']);
}

#-------------------------------------------------------------------------------
# ●書類ログの生成
#-------------------------------------------------------------------------------
sub make_document_log_msg {
	my $self = shift;
	my $new  = shift;
	my $old  = shift;
	return $self->make_log_msg($new, $old, {
		ymd		=> '日付',
		dtype		=> '種別',
		dformat		=> '書式',
		dcode		=> '書類コード',
		title		=> '概要',

		subtotal	=> '税抜',
		tax_rate	=> '税率',
		tax		=> '税額',
		total		=> '総額',

		paid_ymd	=> '決済日',
		paid		=> '決済額',
		remain		=> '残高',

		c_pkey		=> '相手先',
		files		=> 'ファイル'
	},{
		# ignore
	},{
		c_pkey		=> 'client.pkey'
	});
}

################################################################################
# ■ファイル処理ルーチン
################################################################################
#---------------------------------------------------------------------
# ●ファイル名の正規化処理
#---------------------------------------------------------------------
sub format_filename {
	my $self = shift;
	my $pkey = shift;			# primary key
	my $h    = shift;			# filew row data
	my $name = shift =~ tr/A-Z/a-z/r;	# original file name
	my $sha  = shift;			# SHA base64 hash

	# 拡張子チェック
	if ($name !~ /(.*)\.([\w\-]+)$/ || !$self->{allow_file_ext}->{$2}) { 
		return;
	}
	$name = $1;
	my $ext = $2;

	# 取引先名
	my $cname = ($self->load_client($h->{c_pkey}) || {})->{name};
	$cname =~ s!\s+! !g;
	$cname =~ s!\x00-\x1f\\/:\*\?\"\'<>|&]!_!gr;

	# dir
	my ($y,$m,$d) = split('-', $h->{ymd});
	my $subdir = "$y/";
	my $dir    = $self->{pub_dir} . $subdir;
	mkdir($dir);

	return $subdir
		. "$y-$m$d"
		. sprintf("_%05d", $pkey)
		. "_$h->{dformat}_$cname"
		. ".$sha.$ext";
}

#---------------------------------------------------------------------
# ●アップロードの実処理
#---------------------------------------------------------------------
sub save_form_file {
	my $self  = shift;
	my $file  = shift;
	my $fname = shift;
	my $ROBJ  = $self->{ROBJ};
	my $dir   = $self->{pub_dir};

	# 拡張子チェック
	if ($fname !~ /(.*)(\.[\w\-]+\.)([\w\-]+)$/ || !$self->{allow_file_ext}->{$3}) { 
		return 10;
	}
	$fname = $1;
	$fname =~ s/\./_/g;	# Apache使用時安全のために必要
	$fname .= "$2$3";

	# ファイルの保存
	if ($file->{tmp}) {
		if ($ROBJ->move_file($file->{tmp}, "$dir$fname")) { return 21; }
	} else {
		if ($ROBJ->fwrite_lines("$dir$fname", $file->{data})) { return 22; }
	}
	return 0;	# 成功
}

#---------------------------------------------------------------------
# ●ファイルの削除
#---------------------------------------------------------------------
sub delete_document_files {
	my $self = shift;
	my $pkey = shift;
	my $files= shift;
	my $dir  = $self->{pub_dir};

	foreach(@$files) {
		unlink("$dir$_");
		my $sha = $self->get_sha256_from_filename($_);
		$self->remove_from_hash_data_file($pkey, $sha);
	}
}

################################################################################
# ■ハッシュ処理ルーチン
################################################################################
#---------------------------------------------------------------------
# ●shaの取得
#---------------------------------------------------------------------
sub get_sha256_b64url {
	my $self  = shift;
	my $file  = shift;

	if (ref($file)) {	# form file
		if ($file->{tmp}) {
			$file = $file->{tmp};
		} else {
			return Digest::SHA::sha256_base64($file->{data}) =~ tr|+/|-_|r;
		}
	}

	my $sha = Digest::SHA->new("sha256");
	$sha->addfile($file);
	return $sha->b64digest =~ tr|+/|-_|r;;
}

sub get_sha256_from_filename {
	my $self  = shift;
	my $file  = shift;

	return $file =~ /\.([\w\-]+)\.\w+$/ ? $1 : '(sha_hash)';
}

#---------------------------------------------------------------------
# ●ハッシュ値からハッシュデータファイルに変換
#---------------------------------------------------------------------
sub get_hash_data_file {
	my $self = shift;
	my $sha  = shift;
	my $dir  = $self->{pub_dir} . 'hash/';
	mkdir($dir);

	return $dir . substr($sha,0,1) . '/' . $sha;
}

#---------------------------------------------------------------------
# ●ハッシュデータファイルに値を追加
#---------------------------------------------------------------------
sub append_to_hash_data_file {
	my $self = shift;
	my $pkey = shift;
	my $file = $self->get_hash_data_file(shift);
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->{pub_dir} . 'hash/';
	mkdir($dir);
	mkdir($file =~ s|/[^/]*$||r);

	my ($fh, $lines) = $ROBJ->fedit_readlines($file);
	if (grep { $_ == $pkey } @$lines) {
		$ROBJ->fedit_exit($fh);
		return;
	}
	push(@$lines, "$pkey\n");

	$ROBJ->fedit_writelines($fh, $lines);
}

#---------------------------------------------------------------------
# ●ハッシュデータファイルから値を削除
#---------------------------------------------------------------------
sub remove_from_hash_data_file {
	my $self = shift;
	my $pkey = shift;
	my $file = $self->get_hash_data_file(shift);
	my $ROBJ = $self->{ROBJ};

	if (!-e $file) { return; }

	my ($fh, $lines) = $ROBJ->fedit_readlines($file);
	my $del;
	my @ary;
	foreach(@$lines) {
		if ($_ eq "\n")  { next; }
		if ($_ == $pkey) { $del=1; next; }
		push(@ary, $_);
	}
	if (!$del) {
		$ROBJ->fedit_exit($fh);
		return;
	}
	if (@ary) {
		$ROBJ->fedit_writelines($fh, \@ary);
		return;
	}
	#
	# 同じファイルを参照するデータが存在しない
	#
	unlink($file);
	$ROBJ->fedit_exit($fh);

	my $dir = $file =~ s|/[^/]*$||r;
	rmdir($dir);	# もし空なら削除される。
}

1;
