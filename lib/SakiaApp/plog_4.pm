use strict;
################################################################################
# ■その他処理
################################################################################
package SakiaApp::plog;
################################################################################
# ■ログ抽出
################################################################################
my %LogTbl = (
	document=> '書類',
	client	=> '取引先',
	_order	=> [ qw(document client) ]
);

#-------------------------------------------------------------------------------
# ●ログ用のカラム情報
#-------------------------------------------------------------------------------
sub load_log_tbl_info {
	my $self  = shift;
	$self->debug();
	return \%LogTbl;
}

#-------------------------------------------------------------------------------
# ●ログの検索
#-------------------------------------------------------------------------------
sub load_all_logs {
	my $self  = shift;
	my $query = shift;
	my $DB    = $self->{DB};

	# 検索ワード
	my $q = $query->{q};
	$self->normalize_string($q);
	$query->{_q} = $q;

	my %h = (match => {}, not_match => {});
	if ($q ne '') {
		$self->make_search_words(\%h, $q);
		$h{search_cols}  = [ qw(msg) ];
		$h{search_match} = [ qw(tbl tbl_pkey type) ];
	}

	# ユーザー
	my $user = $query->{user};
	if ($user) {
		$h{match}->{u_pkey} = $user;
	}

	# テーブル
	my $tbl = $query->{tbl};
	if ($tbl ne '') {
		$h{match}->{tbl} = $tbl;
	}

	# タイプ指定
	my $type = $query->{type};
	if ($type  =~ /^-(.*)$/) {
		$h{not_match}->{type} = $1;
	} elsif ($type ne '') {
		$h{match}->{type} = $type;
	}

	# date指定
	my $from = $self->normalize_date($query->{from_date});
	my $to   = $self->normalize_date($query->{to_date});
	if ($from) {
		$h{min}->{tm} = $from;
	}
	if ($to) {
		$h{max}->{tm}  = "$to 23:59:59";
	}

	# ソート
	my $sort = $query->{sort};
	if ($sort eq '' || $sort eq '-tm') {
		$h{sort} = [ '-tm', '-l.pkey' ];
	} else {
		$h{sort} = [ $sort, 'l.pkey' ];
	}

	# limit
	my $limit = int($query->{limit});
	$h{limit} = $limit<100 ? 100 : $limit;

	# join user name
	$h{cols}  = ['l.*', 'u.name'];
	$h{ljoin} = {
		table	=> 'usr u',
		left	=> 'u.pkey',
		right	=> 'l.u_pkey'
	};

	my ($ary, $hits) = $DB->select('log l', \%h);

	#------------------------------------------------------------
	# ログの後処理
	#------------------------------------------------------------
	$ary = $self->log_msg_filter( $ary );

	foreach(@$ary) {
		my $tbl = $_->{tbl};
		$_->{target} = $LogTbl{$tbl} || $tbl;
		$_->{link}   = "$tbl/view?pkey=";
	}
	return wantarray ? ($ary, $hits) : $ary;
}

1;
