import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import Session, AttendanceRecord
from users.models import Student
from urllib.parse import parse_qs
from rest_framework_simplejwt.tokens import AccessToken
from django.contrib.auth import get_user_model


class AttendanceConsumer(AsyncWebsocketConsumer):
    """
    WebSocket consumer for teacher's live attendance count
    """

    async def connect(self):
        self.session_id = self.scope['url_route']['kwargs']['session_id']
        self.group_name = f'session_{self.session_id}'

        # Join session group
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        await self.accept()

        # Send current count immediately on connect
        count = await self.get_present_count()
        await self.send(text_data=json.dumps({
            'type': 'attendance_update',
            'total_present': count
        }))

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def attendance_update(self, event):
        # Send attendance update to teacher
        await self.send(text_data=json.dumps({
            'type': 'attendance_update',
            'total_present': event['total_present']
        }))

    @database_sync_to_async
    def get_present_count(self):
        return AttendanceRecord.objects.filter(
            session_id=self.session_id,
            status='present'
        ).count()


class StudentHistoryConsumer(AsyncWebsocketConsumer):

    async def connect(self):
        self.group_name = None  # ← set default FIRST

        # Get token from query string
        query_string = self.scope.get('query_string', b'').decode()
        params = parse_qs(query_string)
        token_list = params.get('token', [])

        if not token_list:
            await self.close()
            return

        try:
            token = AccessToken(token_list[0])
            user_id = token['user_id']
            self.user = await self.get_user(user_id)
        except Exception as e:
            print(f"DEBUG: Auth failed: {e}")
            await self.close()
            return

        self.group_name = f'student_{self.user.id}'
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        await self.accept()
        print(f"DEBUG: Student {self.user.id} connected to history stream")

    async def disconnect(self, close_code):
        if self.group_name:  # ← only discard if group was set
            await self.channel_layer.group_discard(
                self.group_name,
                self.channel_name
            )

    async def history_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'history_update',
            'action': event['action'],
            'session_id': event.get('session_id'),
        }))

    @database_sync_to_async
    def get_user(self, user_id):
        User = get_user_model()
        return User.objects.get(id=user_id)