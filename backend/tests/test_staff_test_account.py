"""Staff test-account setup is isolated from all real Firebase/DB services."""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

import create_staff_test_account as setup


SYNTHETIC_PASSWORD = "SyntheticPasswordOnly!"
SYNTHETIC_UID = "staff-test-synthetic-fixed-uuid"


@pytest.fixture
def isolated_setup(monkeypatch):
    firebase_app = object()
    connection = MagicMock(name="synthetic_connection")
    cursor = MagicMock(name="synthetic_cursor")
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = [{"role_id": 42}, None]
    cursor.lastrowid = 701
    connection.cursor.return_value = cursor
    connection_manager = MagicMock(name="synthetic_connection_manager")
    connection_manager.__enter__.return_value = connection
    database_factory = MagicMock(return_value=connection_manager)
    get_firebase_app = MagicMock(return_value=firebase_app)
    get_user_by_email = MagicMock(side_effect=setup.auth.UserNotFoundError("Synthetic missing user"))
    create_user = MagicMock(return_value=SimpleNamespace(uid=SYNTHETIC_UID))
    update_user = MagicMock(side_effect=AssertionError("Existing users must never be changed"))
    delete_user = MagicMock(side_effect=AssertionError("Firebase users must never be deleted"))
    getpass = MagicMock(side_effect=AssertionError("Password input was not expected"))

    monkeypatch.setattr(setup, "mysql_connection", database_factory)
    monkeypatch.setattr(setup, "get_firebase_app", get_firebase_app)
    monkeypatch.setattr(setup, "settings", SimpleNamespace(
        mysql_host="127.0.0.1", mysql_database="shupick_v2", firebase_project_id="shupick-71b8f"
    ))
    monkeypatch.setattr(setup, "uuid4", lambda: SimpleNamespace(hex="synthetic-fixed-uuid"))
    monkeypatch.setattr(setup, "getpass", getpass)
    monkeypatch.setattr(setup.auth, "get_user_by_email", get_user_by_email)
    monkeypatch.setattr(setup.auth, "create_user", create_user)
    monkeypatch.setattr(setup.auth, "update_user", update_user)
    monkeypatch.setattr(setup.auth, "delete_user", delete_user)

    return SimpleNamespace(
        firebase_app=firebase_app,
        connection=connection,
        cursor=cursor,
        database_factory=database_factory,
        get_firebase_app=get_firebase_app,
        get_user_by_email=get_user_by_email,
        create_user=create_user,
        update_user=update_user,
        delete_user=delete_user,
        getpass=getpass,
    )


def assert_no_account_mutations(isolated_setup):
    isolated_setup.create_user.assert_not_called()
    isolated_setup.update_user.assert_not_called()
    isolated_setup.delete_user.assert_not_called()
    isolated_setup.connection.commit.assert_not_called()
    assert all(
        not call.args[0].lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE", "ALTER"))
        for call in isolated_setup.cursor.execute.call_args_list
    )


def test_check_mode_is_read_only_and_does_not_ask_for_password(isolated_setup, capsys):
    assert setup.main(["--check"]) == 0
    isolated_setup.cursor.execute.assert_any_call("START TRANSACTION READ ONLY")
    isolated_setup.get_user_by_email.assert_called_once_with(
        setup.TEST_EMAIL, app=isolated_setup.firebase_app
    )
    isolated_setup.connection.rollback.assert_called_once()
    isolated_setup.getpass.assert_not_called()
    assert_no_account_mutations(isolated_setup)
    assert "준비 확인 완료" in capsys.readouterr().out


@pytest.mark.parametrize("passwords", [
    ("short", "short"),
    (SYNTHETIC_PASSWORD, "DifferentSyntheticPassword!"),
])
def test_invalid_password_input_never_creates_account(isolated_setup, capsys, passwords):
    isolated_setup.getpass.side_effect = passwords
    assert setup.main([]) == 1
    assert_no_account_mutations(isolated_setup)
    output = capsys.readouterr().out
    assert "계정은 생성하지 않았습니다" in output
    assert all(password not in output for password in passwords)


def test_duplicate_employee_is_refused_before_cloud_account_lookup(isolated_setup, capsys):
    isolated_setup.cursor.fetchone.side_effect = [{"role_id": 42}, {"employee_id": 701}]
    assert setup.main(["--check"]) == 1
    isolated_setup.get_user_by_email.assert_not_called()
    isolated_setup.getpass.assert_not_called()
    assert_no_account_mutations(isolated_setup)
    assert "테스트 직원이 이미 있습니다" in capsys.readouterr().out


def test_duplicate_firebase_email_is_refused_without_password_reset(isolated_setup, capsys):
    isolated_setup.get_user_by_email.side_effect = None
    isolated_setup.get_user_by_email.return_value = SimpleNamespace(uid="existing-synthetic-user")
    assert setup.main([]) == 1
    isolated_setup.getpass.assert_not_called()
    assert_no_account_mutations(isolated_setup)
    assert "Firebase 이메일 계정이 이미 있습니다" in capsys.readouterr().out


def test_missing_hq_support_permission_refuses_account_creation(isolated_setup, capsys):
    isolated_setup.cursor.fetchone.side_effect = [None]
    assert setup.main([]) == 1
    permission_query = isolated_setup.cursor.execute.call_args_list[1].args[0]
    assert "r.role_code='HQ_STAFF'" in permission_query
    assert "r.is_active=TRUE" in permission_query
    assert "p.permission_code='SUPPORT_MANAGE'" in permission_query
    isolated_setup.get_user_by_email.assert_not_called()
    isolated_setup.getpass.assert_not_called()
    assert_no_account_mutations(isolated_setup)
    assert "SUPPORT_MANAGE" in capsys.readouterr().out


@pytest.mark.parametrize("setting_name,incorrect_value", [
    ("mysql_host", "192.0.2.5"),
    ("mysql_database", "not-the-test-database"),
    ("firebase_project_id", "not-the-test-project"),
])
def test_unexpected_project_or_database_is_refused_before_db_access(
    isolated_setup, setting_name, incorrect_value
):
    setattr(setup.settings, setting_name, incorrect_value)
    assert setup.main(["--check"]) == 1
    isolated_setup.database_factory.assert_not_called()
    isolated_setup.get_user_by_email.assert_not_called()
    assert_no_account_mutations(isolated_setup)


def test_new_employee_and_role_share_firebase_uid_and_commit_after_cloud_creation(isolated_setup):
    events = []
    isolated_setup.create_user.side_effect = lambda **kwargs: events.append("firebase_created")
    isolated_setup.connection.commit.side_effect = lambda: events.append("db_committed")
    setup.create_account(SYNTHETIC_PASSWORD, isolated_setup.firebase_app)

    insert_calls = [
        call for call in isolated_setup.cursor.execute.call_args_list
        if call.args[0].lstrip().upper().startswith("INSERT")
    ]
    assert len(insert_calls) == 2
    assert "INSERT INTO employees" in insert_calls[0].args[0]
    assert insert_calls[0].args[1] == (
        SYNTHETIC_UID, setup.TEST_EMPLOYEE_CODE, setup.TEST_EMPLOYEE_NAME, "TEST", "HQ_STAFF"
    )
    assert "INSERT INTO employee_roles" in insert_calls[1].args[0]
    assert insert_calls[1].args[1] == (701, 42)
    isolated_setup.create_user.assert_called_once_with(
        uid=SYNTHETIC_UID,
        email=setup.TEST_EMAIL,
        password=SYNTHETIC_PASSWORD,
        display_name=setup.TEST_EMPLOYEE_NAME,
        disabled=False,
        email_verified=False,
        app=isolated_setup.firebase_app,
    )
    assert events == ["firebase_created", "db_committed"]
    isolated_setup.connection.rollback.assert_not_called()
    isolated_setup.update_user.assert_not_called()
    isolated_setup.delete_user.assert_not_called()


def test_full_creation_checks_then_commits_and_never_prints_password(isolated_setup, capsys):
    isolated_setup.cursor.fetchone.side_effect = [{"role_id": 42}, None, {"role_id": 42}, None]
    isolated_setup.getpass.side_effect = [SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD]
    assert setup.main([]) == 0
    isolated_setup.create_user.assert_called_once()
    isolated_setup.connection.commit.assert_called_once()
    isolated_setup.connection.rollback.assert_called_once()
    output = capsys.readouterr().out
    assert "직원 테스트 계정 생성 및 MySQL 연결 완료" in output
    assert SYNTHETIC_PASSWORD not in output


def test_cloud_creation_failure_rolls_back_uncommitted_employee(isolated_setup):
    isolated_setup.create_user.side_effect = RuntimeError("Synthetic cloud creation failure")
    with pytest.raises(setup.SetupError) as error:
        setup.create_account(SYNTHETIC_PASSWORD, isolated_setup.firebase_app)
    assert "재실행하지 말고" in str(error.value)
    assert "Synthetic cloud creation failure" not in str(error.value)
    isolated_setup.connection.rollback.assert_called_once()
    isolated_setup.connection.commit.assert_not_called()
    isolated_setup.update_user.assert_not_called()
    isolated_setup.delete_user.assert_not_called()


def test_db_insert_failure_never_creates_firebase_user(isolated_setup):
    def execute(statement, parameters=None):
        if statement.lstrip().upper().startswith("INSERT"):
            raise RuntimeError("Synthetic insert failure")

    isolated_setup.cursor.execute.side_effect = execute
    with pytest.raises(RuntimeError, match="Synthetic insert failure"):
        setup.create_account(SYNTHETIC_PASSWORD, isolated_setup.firebase_app)
    isolated_setup.connection.rollback.assert_called_once()
    isolated_setup.connection.commit.assert_not_called()
    isolated_setup.create_user.assert_not_called()


def test_ambiguous_commit_failure_does_not_delete_or_reset_cloud_account(isolated_setup):
    isolated_setup.connection.commit.side_effect = RuntimeError("Synthetic ambiguous commit")
    with pytest.raises(setup.SetupError) as error:
        setup.create_account(SYNTHETIC_PASSWORD, isolated_setup.firebase_app)
    isolated_setup.create_user.assert_called_once()
    isolated_setup.connection.commit.assert_called_once()
    isolated_setup.update_user.assert_not_called()
    isolated_setup.delete_user.assert_not_called()
    assert "재실행하거나 계정을 삭제하지 말고" in str(error.value)
    assert "Synthetic ambiguous commit" not in str(error.value)
    assert SYNTHETIC_PASSWORD not in str(error.value)


def test_unexpected_sdk_error_does_not_leak_exception_configuration(isolated_setup, capsys):
    isolated_setup.get_user_by_email.side_effect = RuntimeError("synthetic-private-key-password")
    assert setup.main(["--check"]) == 1
    assert_no_account_mutations(isolated_setup)
    output = capsys.readouterr().out
    assert "RuntimeError" in output
    assert "synthetic-private-key-password" not in output
