from django.urls import path
from .views import LoginView, RegisterView, DeviceEnrollView, DeviceStatusView

urlpatterns = [
    path('login/', LoginView.as_view(), name='login'),
    path('register/', RegisterView.as_view(), name='register'),
    path('device/enroll/', DeviceEnrollView.as_view(), name='device-enroll'),
    path('device/status/', DeviceStatusView.as_view(), name='device-status'),
]