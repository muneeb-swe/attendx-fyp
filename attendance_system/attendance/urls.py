from django.urls import path
from .views import (
    GenerateQRView,
    RefreshQRView,
    StopSessionView,
    SessionAttendanceView,
    EditAttendanceView,
    SubmitAttendanceView,
    MarkAttendanceView,
    TeacherClassesView,
    StudentAttendanceHistoryView,
)

urlpatterns = [
    path('generate-qr/', GenerateQRView.as_view(), name='generate-qr'),
    path('session/<int:session_id>/refresh-qr/', RefreshQRView.as_view(), name='refresh-qr'),
    path('session/<int:session_id>/stop/', StopSessionView.as_view(), name='stop-session'),
    path('session/<int:session_id>/attendance/', SessionAttendanceView.as_view(), name='session-attendance'),
    path('record/<int:record_id>/edit/', EditAttendanceView.as_view(), name='edit-attendance'),
    path('session/<int:session_id>/submit/', SubmitAttendanceView.as_view(), name='submit-attendance'),
    path('mark/', MarkAttendanceView.as_view(), name='mark-attendance'),
    path('teacher/classes/', TeacherClassesView.as_view(), name='teacher-classes'),
    path('student/history/', StudentAttendanceHistoryView.as_view(), name='student-history'),
]