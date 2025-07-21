use strict;
#-------------------------------------------------------------------------------
# pdf-logger
#						(C)2024 nabe@abk
#-------------------------------------------------------------------------------
package SakiaApp::plog;
use Sakia::AutoLoader;
use Time::Local;
use Digest::SHA ();
#-------------------------------------------------------------------------------
our $VERSION = '1.00';
################################################################################
# Constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{DB}   = shift;
	$self->{VERSION} = $VERSION;

	$self->{main_skel}  = '_menu';
	$self->{login_skel} = '_login';
	$self->{frame_skel} = '_frame';

	return $self;
}

################################################################################
# main
################################################################################
sub main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$self->authorization();

	$ROBJ->read_query();
	$ROBJ->read_form();

	#-------------------------------------------------------------
	# POST action
	#-------------------------------------------------------------
	if ($ROBJ->{POST_ERR}) {
		$self->json_mode();
		return $self->output_html( $ROBJ->generate_json({
			ret => -1,
			msg => $ROBJ->clear_msg("\n")
		}));
	}
	if ($ROBJ->{POST}) {
		my $action = $ROBJ->{Form}->{action};
		if ($action =~ /^(?:\w+_)?_ajax_\w+$/) {
			my $data = $self->ajax_function( $action );

			# Append debug message
			if ($ROBJ->{Develop} && ref($data) eq 'HASH'
			&& (my $err = $ROBJ->join_msg("\n", $ROBJ->clear_error("\n"), $ROBJ->clear_msg("\n"), $ROBJ->clear_debug("\n"))) ) {
				$data->{_debug} = $err;
			}

			$self->{action_data} = $ROBJ->generate_json( $data );
		}
	}

	#-------------------------------------------------------------
	# call skeleton
	#-------------------------------------------------------------
	my $skel = $self->select_skeleton( substr($ENV{PATH_INFO},1) );

	$self->output_html( $skel );
}

#-------------------------------------------------------------------------------
# login session
#-------------------------------------------------------------------------------
sub authorization {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	my $cookie  = $ROBJ->get_cookie();
	my $session = $cookie->{session};
	if (ref $session eq 'HASH') {
		$auth->auth_session($session->{id}, $session->{sid});
	}
}

#-------------------------------------------------------------------------------
# select skeleton
#-------------------------------------------------------------------------------
sub select_skeleton {
	my $self = shift;
	my $_skel= shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if ($_skel ne '' && !$auth->{ok}) {
		$ROBJ->redirect( $ROBJ->{myself} );
	}

	my ($dir,$file) = $self->parse_skel( $_skel );
	my $skel = "$dir$file" || ($auth->{ok} ? $self->{main_skel} : $self->{login_skel});

	if ($skel ne '' && !$ROBJ->find_skeleton($skel)) {
		$ROBJ->redirect( $ROBJ->{myself} );
	}

	$self->{skel}      = $_skel;
	$self->{skel_dir}  = $dir;
	$self->{skel_name} = $file;
	$self->{thisurl}   = $ROBJ->{myself2} . $_skel;
	return $skel;
}
sub parse_skel {
	my ($self, $str) = @_;
	if ($str =~ m|\.\.|) { return '-error-'; }	# safety
	if ($str !~ m|^((?:[A-Za-z0-9][\w\-]*/)*)([A-Za-z0-9][\w\-]*)?$|) { return '-error-'; }
	my $b = ($1 ne '' && $2 eq '') ? 'index' : $2;
	return wantarray ? ($1,$b) : "$1$b";
}

#-------------------------------------------------------------------------------
# output html
#-------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $skel = shift;
	my $ROBJ = $self->{ROBJ};

	my $out;
	if ($self->{action_is_main}) {
		$out = $self->{action_data};
	} else {
		$out = $ROBJ->call( $skel );
	}

	my $frame = $self->{frame_skel};
	if ($frame) {
		$out = $ROBJ->call($frame, $out);
	}
	$ROBJ->output($out);
}

#-------------------------------------------------------------------------------
# Ajax
#-------------------------------------------------------------------------------
sub ajax_function {
	my $self = shift;
	$self->json_mode();

	my $h = $self->do_ajax_function(@_);
	if (!ref($h)) { return { ret => $h } }
	if (ref($h) ne 'ARRAY') { return $h; }

	my %r = (ret => shift(@$h));
	if (@$h) {
		my $v = shift(@$h);
		$r{ref($v) ? 'errs' : 'msg'} = $v;
	}
	if (@$h) { $r{data} = shift(@$h); }
	return \%r;
}

sub do_ajax_function {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};

	if ($func ne '_ajax_login' && !$ROBJ->{Auth}->{ok}) {
		return [ -991, 'require login' ];
	}

	my $r;
	eval { $r = $self->$func( $ROBJ->{Form} ); };
	if (!$@) { return $r; }

	# eval error
	return [ -999, $@ ];
}

#-------------------------------------------------------------------------------
# json_mode
#-------------------------------------------------------------------------------
sub json_mode {
	my $self = shift;
	$self->{action_is_main} = 1;
	$self->{frame_skel} = undef;
}

################################################################################
# functions
################################################################################
#-------------------------------------------------------------------------------
# login
#-------------------------------------------------------------------------------
sub _ajax_login {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $id   = $form->{id};

	if ($self->{login_secret} ne '' && $form->{secret} ne $self->{login_secret}) {
		return { ret=>1, msg=>$ROBJ->translate('Incorrect ID or password.') };
	}

	my $r = $auth->login($id, $form->{pass});
	if ($r->{ret}) {	# error
		if (!$ROBJ->{Develop}) { $r->{ret} = 1; }
		return $r;
	}

	# login
	$ROBJ->set_cookie('session', {
		id  => $auth->{id},
		sid => $r->{sid}
	}, $auth->{expires});
	return 0;
}

################################################################################
# ■文字処理関連
################################################################################
#-------------------------------------------------------------------------------
# ●文字表記の正規化
#-------------------------------------------------------------------------------
sub normalize_string {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $Jzen2han = $ROBJ->loadpm('Code::Jzen2han');

	foreach(@_) {
		if ($_ =~ /^[\x00-\x7f]*$/) { next; }

		$Jzen2han->utf8_zen2han    (\$_);
		$Jzen2han->utf8_hankana2zen(\$_);

		$_ =~ s/㈱|\(株\)|（株）/株式会社/g;
		$_ =~ s/㈲|\(有\)|（有）/有限会社/g;
		$_ =~ s/(^|[\x00-\x7f])（([\x00-\x7f]|$)/$1($2/g;
		$_ =~ s/(^|[\x00-\x7f])）([\x00-\x7f]|$)/$1)$2/g;
	}
	$ROBJ->normalize_dest(@_);	# trim含む
	return $ROBJ->esc_dest(@_);
}

#-------------------------------------------------------------------------------
# ●メモの正規化
#-------------------------------------------------------------------------------
sub normalize_memo {
	my $self = shift;
	my $memo = shift;
	my $ROBJ = $self->{ROBJ};

	$memo =~ s/^\s+//;
	$memo =~ s/\s+$//;
	$memo =~ s/\r\n/\n/g;
	return $ROBJ->esc_amp( $memo );
}

#-------------------------------------------------------------------------------
# ●タグ表記の正規化
#-------------------------------------------------------------------------------
sub normalize_tags {
	my $self = shift;
	my $tags = shift;
	my $ROBJ = $self->{ROBJ};

	$self->normalize_string($tags);

	my %h;
	my @ary;
	$tags =~ s/、/,/g;
	foreach(split(/[ ,]+/, $tags)) {
		if ($_ eq '' || $h{$_}) { next; }
		$h{$_}=1;
		push(@ary, $_);
	}
	return join(' ', @ary);
}

#-------------------------------------------------------------------------------
# ●タグのパース
#-------------------------------------------------------------------------------
sub parse_tags {
	my $self = shift;
	my @tags = map { $_ ? "<span class=\"tag\">$_</span>" : '' } split(' ', join(' ', @_));
	return join('', @tags);
}

################################################################################
# ■日付関連
################################################################################
#-------------------------------------------------------------------------------
# ●日付の確認
#-------------------------------------------------------------------------------
sub normalize_date {
	my $self = shift;

	foreach(@_) {
		$_ =~ tr/\//-/;
		if ($_ !~ /^(\d{4})-(\d\d?)-(\d\d?)$/) {
			$_ = undef;
			next;
		}
		my $y = $1;
		my $m = $2;
		my $d = $3;

		$_ = undef;
		eval {
			timegm(0,0,0,$d,$m-1,$y);	# error check
			$_ = sprintf("%04d-%02d-%02d", $y, $m, $d);
		}
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●日時のパース
#-------------------------------------------------------------------------------
sub parse_date {
	my $self = shift;
	my $date = shift;
	$date =~ s/ .*$//;
	return $date;
}

sub parse_datetm {
	my $self = shift;
	my $date = shift;
	my $ROBJ = $self->{ROBJ};
	my $ymd  = $self->{yyyymmdd} ||= $ROBJ->print_tmf('%Y-%m-%d');

	if ($date !~ /^([^ ]+) (.+)/) { return $date; }

	return ($1 ne $ymd) ? $1 : "<span class=\"datetm-tm\">$2</span>";
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●js/cssファイルの登録
#-------------------------------------------------------------------------------
sub regist_js {
	my $self = shift;
	push(@{ $self->{jsfiles} ||=[] }, @_);
}
sub regist_js_module {
	my $self = shift;
	push(@{ $self->{jsmodfiles} ||=[] }, @_);
}
sub load_jscss {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $base = $ROBJ->{Basepath};

	my @ary = @{ $self->{$name . 'files'} || []};

	my %h;
	@ary = grep { $h{$_}++; $h{$_}<2 } @ary;
	foreach(@ary) {
		if ($_ =~ m!^/|^https?://!i) { next; }
		$_ = $base . $_ . '?' . $ROBJ->get_lastmodified( $_ );
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●検索ワードの生成
#-------------------------------------------------------------------------------
sub make_search_words {
	my $self = shift;
	my $h    = shift;
	my @ary  = split(/ +/, shift);
	$h->{search_words} = [                      grep { $_ !~ /^-./ } @ary ];
	$h->{search_not}   = [ map { substr($_,1) } grep { $_ =~ /^-./ } @ary ];
}

#-------------------------------------------------------------------------------
# ●今日の日付
#-------------------------------------------------------------------------------
sub get_today {
	my $self = shift;
	return $self->{ROBJ}->print_tmf('%Y-%m-%d');
}

#-------------------------------------------------------------------------------
# ●金額の書式化
#-------------------------------------------------------------------------------
sub printc {
	my $self = shift;
	my $n = shift || 0;
	while($n =~ s/^(-?\d+)(\d\d\d)/$1,$2/) {};
	# if ($n < 0) { $n = "<span class=\"minus\">$n</span>"; }
	return $n;
}

################################################################################
# ■ログ
################################################################################
#-------------------------------------------------------------------------------
# ●ログの記録
#-------------------------------------------------------------------------------
sub log {
	my $self = shift;
	my ($table, $pkey, $type, $msg, $r_pkey, $c_pkey) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	# 関連契約
	if ($r_pkey) {
		my $add = '契約: ' . $self->log_receipt_pkey($r_pkey);
		$msg .= ($msg eq '' ? '' : "\n") . $add;
	}
	# 移動相手
	if ($c_pkey) {
		if (1) {
			my $add = '相手: ' . $self->log_client_pkey($c_pkey);
			$msg .= ($msg eq '' ? '' : "\n") . $add;
		}
		my $h      = $self->load_client($c_pkey);
		my $upnode = $h->{upnode};
		if ($upnode) {
			my $add = '相手所属: ' . $self->log_client_pkey($upnode);
			$msg .= ($msg eq '' ? '' : "\n") . $add;
		}
	}

	# ホスト名逆引き
	$ROBJ->resolve_host();

	my %h = (
		tbl	=> $table,
		tbl_pkey=> $pkey,
		type	=> $type,
		msg	=> $msg
	);
	$h{ip}   = $ENV{REMOTE_ADDR};
	$h{host} = $ENV{REMOTE_HOST};
	$ROBJ->trim_dest($h{host});
	$ROBJ->esc_dest($h{host});

	# 操作者
	if ($auth->{ok}) {
		$h{u_pkey} = $auth->{pkey};
	}

	$DB->insert('log', \%h);
}

#-------------------------------------------------------------------------------
# ●ログメッセージの生成
#-------------------------------------------------------------------------------
my %COL_INFO = (
	memo 	=> 'メモ'
);
my %COL_IGNORE = map { $_ => 1 } qw(
	create_tm update_tm
);

sub make_log_msg {
	my $self   = shift;
	my $new    = shift;
	my $old    = shift;
	my $h      = shift || {};
	my $ignore = shift || {};
	my $v_map  = shift || {};
	my $ROBJ   = $self->{ROBJ};

	my @ary;
	foreach(sort(keys(%$new))) {
		if ($_ eq 'pkey')	{ next; }
		if ($_ =~ /^[_\*]/)	{ next; }
		if ($ignore->{$_})	{ next; }
		if ($COL_IGNORE{$_})	{ next; }
		if ($old->{$_} eq $new->{$_}) { next; }

		my $n = $h->{$_} || $COL_INFO{$_} || $_;
		my $x = $old->{$_};
		my $y = $new->{$_};
		if (!ref($x)) { $ROBJ->esc_dest($x); }
		if (!ref($y)) { $ROBJ->esc_dest($y); }

		if ($_ eq 'files') {		# "(sha256).ext" に変換
			my @ax = map { s/^[^\.]+\.([^\.]+)\./$1./r } split(/\t/, $x);
			my @ay = map { s/^[^\.]+\.([^\.]+)\./$1./r } split(/\t/, $y);
			my $num=0;
			while(@ax || @ay) {
				$num++;
				$x = shift(@ax);
				$y = shift(@ay);
				if ($x eq $y) { next; }
				foreach($x, $y) {
					if ($_ eq '') { next; }
					my ($sha, $ext) = split(/\./, $_, 2);
					$_ = "<sha hash=\"$sha\">" . substr($sha, 0, 12) . ".$ext</sha>";
				}
				push(@ary, %$old ? "$n$num: $x → $y" : "$n$num: $y");
			}
			next;
		}

		if ($v_map->{$_}) {
			my $m = $v_map->{$_};
			if ($m eq 'flag') {
				$x = $x ? 'on' : 'off';
				$y = $y ? 'on' : 'off';
				if ($x eq $y) { next; }
			} elsif ($m eq 'client.pkey') {
				$x = $self->log_client_pkey($x);
				$y = $self->log_client_pkey($y);
			} elsif (ref($m) eq 'CODE') {
				$x = &$m($x);
				$y = &$m($y);
			} else {
				$x = $m->{$x} || $x;
				$y = $m->{$y} || $y;
			}
		} elsif ($_ =~ /_tm$/) {
			$x =~ s/ 00:00:00$//;
			$y =~ s/ 00:00:00$//;
		} elsif ($_ eq 'memo') {
			$x = ($ROBJ->mb_length($x) || 0) . '文字';
			$y = ($ROBJ->mb_length($y) || 0) . '文字';
		}
		push(@ary, %$old ? "$n: $x → $y" : "$n: $y");
	}
	# foreach end

	if ($new->{_file}) {
		my $h    = $new->{_file};
		my $file = $self->save_log_file( $h );
		if ($file) {
			my $title = $ROBJ->esc($h->{title});
			push(@ary, "添付: <attach file=\"$file\">$h->{title}</attach>");
		}
	}
	if ($new->{_log_memo}) {
		push(@ary, "【メモ】" . $new->{_log_memo});
	}
	return join("\n", @ary);
}

sub log_client_pkey {
	my $self = shift;
	my $pkey = shift;
	if (!$pkey) { return ''; }
	return "<client pkey=\"$pkey\">" . $self->load_client_name($pkey) . "</client>";
}

#-------------------------------------------------------------------------------
# ●ログ添付画像の保存
#-------------------------------------------------------------------------------
sub save_log_file {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	if ($file->{_no_save}) { return; }
	if ($file->{__saved})  { return $file->{__saved}; }	# saved

	if ($file->{name} !~ /(\.[\w-]+)$/) { return; }		# 拡張子なし
	my $ext = $1;
	$ext =~ tr/A-Z/a-z/;

	my $now  = $ROBJ->{Now};
	my ($pub, $dir) = $self->get_pubdir('log/', $ext =~ /\.xlsx|\.csv/i ? 'xlsx' : "$now->{year}/$now->{mon}");
	my $fname;
	{
		my $base = $ROBJ->print_tmf("%Y%m%d-%H%M");
		my $s    = $now->{sec};
		foreach(0..40) {
			$fname = $base . sprintf("%02d", $s+$_) . $ext;
			if (!-e "$pub$dir$fname") { last; }
		}
	}

	my $r = $self->save_file($file, "$pub$dir$fname");
	if ($r) {
		return;
	}
	return ($file->{__saved} = "$dir$fname");
}

#-------------------------------------------------------------------------------
# ●ログのロード
#-------------------------------------------------------------------------------
sub load_logs {
	my $self = shift;
	my $table= shift;
	my $pkey = shift;
	my $limit= shift;
	my @limit= $limit ? ('*limit', $limit) : ();
	my $DB   = $self->{DB};
	my $ary  = $DB->select('log l', {
		cols	=> ['l.*', 'u.name'],
		match	=> {
				tbl	=> $table,
				tbl_pkey=> $pkey
			},
		sort	=> ['-tm', '-l.pkey'],
		limit	=> $limit,
		ljoin	=> {
				table	=> 'usr u',
				left	=> 'u.pkey',
				right	=> 'l.u_pkey'
			}
		});
	return $self->log_msg_filter( $ary );
}

sub log_msg_filter {
	my $self = shift;
	my $ary  = shift;
	my $ROBJ = $self->{ROBJ};
	my $url  = $ROBJ->{myself2};
	my $pub  = $ROBJ->{Basepath} . $self->{pub_dir};
	my %rep  = (
		client    => "${url}client/view?pkey="
	);

	foreach(@$ary) {
		$_->{msg} =~ s!<(client) +pkey="(\d+)">([^<]*)</\1>!<a href="$rep{$1}$2">$3</a>!g;
		$_->{msg} =~ s|<sha hash="([^\"]*)">([^<]*)</sha>|<span title="$1">$2</span>|g;
		$_->{msg} =~ s|<attach file="([^\"]*)">([^<]*)</attach>|<a href="$pub$1">$2</a>|g;
		$_->{msg} =~ s|<yen>(-?\d+)</yen>|$self->printc($1) . "円"|eg;
	}
	return $ary;
}


1;
