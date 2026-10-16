from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    LoginView,
    LogoutView,
    DeviceEnrollView,
    DeviceStatusView,
    VerifyTokenView,
)

urlpatterns = [
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('device/enroll/', DeviceEnrollView.as_view(), name='device-enroll'),
    path('device/status/', DeviceStatusView.as_view(), name='device-status'),
    path('verify/', VerifyTokenView.as_view(), name='verify-token'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),
]