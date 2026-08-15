import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import Session, AttendanceRecord
from users.models import Student, Teacher
from urllib.parse import parse_qs
from rest_framework_simplejwt.tokens import AccessToken
from django.contrib.auth import get_user_model


class AttendanceConsumer(AsyncWebsocketConsumer):

    async def connect(self):
        self.group_name = None
        self.session_id = self.scope['url_route']['kwargs']['session_id']

        print(
            f"WEBSOCKET CONNECT: session={self.session_id}",
            flush=True
        )

        query_string = self.scope.get('query_string', b'').decode()

        params = parse_qs(query_string)
        token_list = params.get('token', [])

        print(
            f"WEBSOCKET TOKEN PRESENT: {bool(token_list)}",
            flush=True
        )

        if not token_list:
            print("WEBSOCKET REJECTED: NO TOKEN", flush=True)
            await self.close()
            return

        try:
            token = AccessToken(token_list[0])

            print("WEBSOCKET JWT VALID", flush=True)

            user_id = token['user_id']

            print(
                f"WEBSOCKET USER ID: {user_id}",
                flush=True
            )

            self.user = await self.get_user(user_id)

            print(
                f"WEBSOCKET USER: {self.user.username}, "
                f"ROLE: {self.user.role}",
                flush=True
            )

            if self.user.role != 'teacher':
                print(
                    "WEBSOCKET REJECTED: USER IS NOT TEACHER",
                    flush=True
                )
                await self.close()
                return

            owns = await self.verify_session_ownership(
                self.session_id,
                self.user
            )

            print(
                f"WEBSOCKET SESSION OWNERSHIP: {owns}",
                flush=True
            )

            if not owns:
                print(
                    "WEBSOCKET REJECTED: SESSION NOT OWNED BY TEACHER",
                    flush=True
                )
                await self.close()
                return

        except Exception as e:
            print(
                f"WEBSOCKET AUTH ERROR: {type(e).__name__}: {e}",
                flush=True
            )
            await self.close()
            return

        self.group_name = f"session_{self.session_id}"

        print(
            f"WEBSOCKET AUTHORIZED: teacher={self.user.username}, "
            f"session={self.session_id}, group={self.group_name}",
            flush=True
        )

        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )

        await self.accept()

        print(
            "WEBSOCKET ACCEPTED",
            flush=True
        )

    @database_sync_to_async
    def verify_session_ownership(self, session_id, user):
        try:
            teacher = Teacher.objects.get(user=user)
            Session.objects.get(id=session_id, teacher=teacher)
            return True
        except (Teacher.DoesNotExist, Session.DoesNotExist):
            return False

    @database_sync_to_async
    def get_user(self, user_id):
        User = get_user_model()
        return User.objects.get(id=user_id)

    async def disconnect(self, close_code):
        if self.group_name:
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
            await self.close()
            return

        self.group_name = f'student_{self.user.id}'
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        await self.accept()

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