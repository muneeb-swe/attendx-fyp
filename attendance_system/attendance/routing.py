from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(
        r'ws/attendance/session/(?P<session_id>\d+)/$',
        consumers.AttendanceConsumer.as_asgi()
    ),
    re_path(
        r'ws/attendance/student/history/$',
        consumers.StudentHistoryConsumer.as_asgi()
    ),
]