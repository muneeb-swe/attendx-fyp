import asyncio
import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import Session, AttendanceRecord
from users.models import Student, Teacher
from rest_framework_simplejwt.tokens import AccessToken
from django.contrib.auth import get_user_model


# How long a new socket may stay open without sending its auth message.
AUTH_TIMEOUT_SECONDS = 5

# Application-level close codes (4000-4999 are reserved for applications).
WS_CLOSE_UNAUTHORIZED = 4401


class FirstMessageAuthMixin:
    """
    Authenticate a WebSocket with its first message instead of a URL query
    string, so the access token never appears in the connection URL and so
    never ends up in access logs or proxy logs.

    The client connects, then sends {"type": "auth", "token": "<access token>"}.
    The socket is accepted straight away so the server can read that message,
    but it joins no group, and so receives nothing, until the token has been
    validated. A socket that does not authenticate within
    AUTH_TIMEOUT_SECONDS is closed.

    Subclasses implement on_authenticated(user): check permissions, join a
    group, and return True to accept the user or False to refuse.
    """

    group_name = None
    user = None
    authenticated = False
    _auth_deadline_task = None

    async def connect(self):
        await self.accept()
        self._auth_deadline_task = asyncio.ensure_future(self._auth_deadline())

    async def _auth_deadline(self):
        await asyncio.sleep(AUTH_TIMEOUT_SECONDS)
        if not self.authenticated:
            await self.close(code=WS_CLOSE_UNAUTHORIZED)

    async def receive(self, text_data=None, bytes_data=None):
        if self.authenticated:
            # Clients send nothing after authenticating; ignore anything else.
            return

        user = await self._user_from_auth_message(text_data)
        if user is None:
            await self.close(code=WS_CLOSE_UNAUTHORIZED)
            return

        self.user = user
        if not await self.on_authenticated(user):
            await self.close(code=WS_CLOSE_UNAUTHORIZED)
            return

        self.authenticated = True
        if self._auth_deadline_task:
            self._auth_deadline_task.cancel()
        await self.send(text_data=json.dumps({'type': 'auth_ok'}))

    async def _user_from_auth_message(self, text_data):
        try:
            message = json.loads(text_data)
            if message.get('type') != 'auth':
                return None
            token = AccessToken(message['token'])
            return await self.get_user(token['user_id'])
        except Exception:
            return None

    async def on_authenticated(self, user):
        raise NotImplementedError

    async def disconnect(self, close_code):
        if self._auth_deadline_task:
            self._auth_deadline_task.cancel()
        if self.group_name:
            await self.channel_layer.group_discard(
                self.group_name,
                self.channel_name
            )

    @database_sync_to_async
    def get_user(self, user_id):
        User = get_user_model()
        return User.objects.get(id=user_id)


class AttendanceConsumer(FirstMessageAuthMixin, AsyncWebsocketConsumer):

    async def connect(self):
        self.session_id = self.scope['url_route']['kwargs']['session_id']
        await super().connect()

    async def on_authenticated(self, user):
        if user.role != 'teacher':
            return False

        if not await self.verify_session_ownership(self.session_id, user):
            return False

        self.group_name = f"session_{self.session_id}"
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        return True

    @database_sync_to_async
    def verify_session_ownership(self, session_id, user):
        try:
            teacher = Teacher.objects.get(user=user)
            Session.objects.get(id=session_id, teacher=teacher)
            return True
        except (Teacher.DoesNotExist, Session.DoesNotExist):
            return False

    async def attendance_update(self, event):
        # Send attendance update to teacher
        await self.send(text_data=json.dumps({
            'type': 'attendance_update',
            'total_present': event['total_present'],
            'auto_stopped': event.get('auto_stopped', False),
        }))

    @database_sync_to_async
    def get_present_count(self):
        return AttendanceRecord.objects.filter(
            session_id=self.session_id,
            status='present'
        ).count()


class StudentHistoryConsumer(FirstMessageAuthMixin, AsyncWebsocketConsumer):

    async def on_authenticated(self, user):
        self.group_name = f'student_{user.id}'
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        return True

    async def history_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'history_update',
            'action': event['action'],
            'session_id': event.get('session_id'),
        }))
