import json
from unittest import mock

from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import RefreshToken

from users.models import User, Student, Teacher
from .models import Class, Session
from .routing import websocket_urlpatterns
from .consumers import WS_CLOSE_UNAUTHORIZED

application = URLRouter(websocket_urlpatterns)


def tokens_for(user):
    """Build tokens synchronously: with the token blacklist app installed,
    RefreshToken.for_user writes to the database, which cannot be done from
    inside an async test."""
    refresh = RefreshToken.for_user(user)
    return str(refresh.access_token), str(refresh)


def auth_message(token):
    return json.dumps({'type': 'auth', 'token': token})


class WebSocketAuthTests(TransactionTestCase):
    """
    WebSockets authenticate with a first message, not a ?token= query
    string, so the token never appears in the URL (and so never in logs).
    TransactionTestCase because the consumers query the database from a
    worker thread, which cannot see a TestCase's uncommitted transaction.
    """

    def setUp(self):
        self.teacher_user = User.objects.create_user(
            username='teacher1', password='pass123', role='teacher')
        self.teacher = Teacher.objects.create(
            user=self.teacher_user, department='CS', employee_id='EMP1')
        self.student_user = User.objects.create_user(
            username='student1', password='pass123', role='student')
        Student.objects.create(
            user=self.student_user, roll_number='CS-101', department='CS', batch='2026')
        self.class_obj = Class.objects.create(
            name='Data Structures', subject='CS201', teacher=self.teacher)
        self.session = Session.objects.create(
            class_ref=self.class_obj, teacher=self.teacher, qr_token='x',
            expires_at='2999-01-01T00:00:00Z', is_active=True, present_count=0)
        self.path = f'/ws/attendance/session/{self.session.id}/'

        other_user = User.objects.create_user(
            username='teacher2', password='pass123', role='teacher')
        Teacher.objects.create(user=other_user, department='EE', employee_id='EMP2')

        self.teacher_access, self.teacher_refresh = tokens_for(self.teacher_user)
        self.student_access, _ = tokens_for(self.student_user)
        self.other_teacher_access, _ = tokens_for(other_user)

    async def open_and_send(self, path, first_message):
        communicator = WebsocketCommunicator(application, path)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.send_to(text_data=first_message)
        return communicator

    async def assert_closed_unauthorized(self, communicator):
        output = await communicator.receive_output(timeout=2)
        self.assertEqual(output['type'], 'websocket.close')
        self.assertEqual(output['code'], WS_CLOSE_UNAUTHORIZED)

    # ---- teacher session socket ----

    async def test_valid_teacher_token_is_accepted_and_receives_updates(self):
        communicator = await self.open_and_send(
            self.path, auth_message(self.teacher_access))
        self.assertEqual(await communicator.receive_json_from(), {'type': 'auth_ok'})

        await get_channel_layer().group_send(
            f'session_{self.session.id}',
            {'type': 'attendance_update', 'total_present': 3, 'auto_stopped': False},
        )
        update = await communicator.receive_json_from()
        self.assertEqual(update['type'], 'attendance_update')
        self.assertEqual(update['total_present'], 3)
        await communicator.disconnect()

    async def test_socket_receives_nothing_before_it_authenticates(self):
        communicator = WebsocketCommunicator(application, self.path)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        await get_channel_layer().group_send(
            f'session_{self.session.id}',
            {'type': 'attendance_update', 'total_present': 9, 'auto_stopped': False},
        )
        self.assertTrue(await communicator.receive_nothing(timeout=0.3))
        await communicator.disconnect()

    async def test_socket_that_never_authenticates_is_closed(self):
        with mock.patch('attendance.consumers.AUTH_TIMEOUT_SECONDS', 0.2):
            communicator = WebsocketCommunicator(application, self.path)
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await self.assert_closed_unauthorized(communicator)

    async def test_token_in_url_is_no_longer_accepted(self):
        communicator = WebsocketCommunicator(
            application, f'{self.path}?token={self.teacher_access}')
        await communicator.connect()

        await get_channel_layer().group_send(
            f'session_{self.session.id}',
            {'type': 'attendance_update', 'total_present': 1, 'auto_stopped': False},
        )
        # Not authenticated by the URL, so it never joined the group.
        self.assertTrue(await communicator.receive_nothing(timeout=0.3))
        await communicator.disconnect()

    async def test_garbage_token_rejected(self):
        communicator = await self.open_and_send(self.path, auth_message('garbage'))
        await self.assert_closed_unauthorized(communicator)

    async def test_refresh_token_rejected(self):
        communicator = await self.open_and_send(
            self.path, auth_message(self.teacher_refresh))
        await self.assert_closed_unauthorized(communicator)

    async def test_malformed_first_messages_rejected(self):
        for bad in ['not json', '[]', '{}', json.dumps({'type': 'hello'}),
                    json.dumps({'type': 'auth'})]:
            with self.subTest(first_message=bad):
                communicator = await self.open_and_send(self.path, bad)
                await self.assert_closed_unauthorized(communicator)

    async def test_student_cannot_join_a_teacher_session_socket(self):
        communicator = await self.open_and_send(
            self.path, auth_message(self.student_access))
        await self.assert_closed_unauthorized(communicator)

    async def test_teacher_cannot_join_a_session_they_do_not_own(self):
        communicator = await self.open_and_send(
            self.path, auth_message(self.other_teacher_access))
        await self.assert_closed_unauthorized(communicator)

    # ---- student history socket ----

    async def test_student_history_socket_authenticates_and_receives(self):
        communicator = await self.open_and_send(
            '/ws/attendance/student/history/',
            auth_message(self.student_access))
        self.assertEqual(await communicator.receive_json_from(), {'type': 'auth_ok'})

        await get_channel_layer().group_send(
            f'student_{self.student_user.id}',
            {'type': 'history_update', 'action': 'submitted', 'session_id': 5},
        )
        update = await communicator.receive_json_from()
        self.assertEqual(update['type'], 'history_update')
        self.assertEqual(update['session_id'], 5)
        await communicator.disconnect()

    async def test_student_history_socket_rejects_bad_token(self):
        communicator = await self.open_and_send(
            '/ws/attendance/student/history/', auth_message('garbage'))
        await self.assert_closed_unauthorized(communicator)
