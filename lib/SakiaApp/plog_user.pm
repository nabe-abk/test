use strict;
################################################################################
# user
################################################################################
package SakiaApp::plog;
################################################################################
# ■ユーザー管理
################################################################################
#-------------------------------------------------------------------------------
# ●ユーザー追加
#-------------------------------------------------------------------------------
sub user__ajax_add {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	$form->{id} = $form->{msys_id};
	delete $form->{msys_id};

	return $auth->add_user($form);
}

#-------------------------------------------------------------------------------
# ●ユーザー編集
#-------------------------------------------------------------------------------
sub user__ajax_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	return $auth->edit_user($form);
}

#-------------------------------------------------------------------------------
# ●ユーザー削除
#-------------------------------------------------------------------------------
sub user__ajax_delete {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	my $id = $form->{id};
	my $info = $auth->load_info($id);
	if (!$info) {
		return [ 10, 'ユーザーがみつかりません。' ];
	}
	if ($self->user__check_used($info->{pkey})) {
		return [ 20, 'このユーザーは使用済のため削除できません。' ];
	}
	return $auth->delete_user($id);
}

#-------------------------------------------------------------------------------
# ●自分自身のユーザー情報変更
#-------------------------------------------------------------------------------
sub user__ajax_self_change {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	delete $form->{id};	# 使用しないが、念の為

	return $auth->change_info($form);
}

#-------------------------------------------------------------------------------
# ●ユーザーの使用状況確認
#-------------------------------------------------------------------------------
sub user__check_used {
	my $self = shift;
	my $pkey = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}
	return $DB->select_match_pkey1('log', 'u_pkey', $pkey);
}

1;
