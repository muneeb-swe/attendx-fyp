from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from django.contrib.auth import authenticate
from rest_framework_simplejwt.tokens import RefreshToken
from cryptography.hazmat.primitives.serialization import load_pem_public_key, load_der_public_key
import base64

from .models import User, Student, Teacher, Device
from .serializers import (
    LoginSerializer,
    RegisterSerializer,
    DeviceEnrollSerializer,
)


# Helper function to generate tokens
def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {
        'refresh': str(refresh),
        'access': str(refresh.access_token),
    }


class LoginView(APIView):

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(
                {'error': 'Invalid data'},
                status=status.HTTP_400_BAD_REQUEST
            )

        username = serializer.validated_data['username']
        password = serializer.validated_data['password']

        user = authenticate(username=username, password=password)
        if user is None:
            return Response(
                {'error': 'Invalid username or password'},
                status=status.HTTP_401_UNAUTHORIZED
            )

        tokens = get_tokens_for_user(user)

        response_data = {
            'access_token': tokens['access'],
            'refresh_token': tokens['refresh'],
            'role': user.role,
            'name': f"{user.first_name} {user.last_name}",
            'username': user.username,
        }

        if user.role == 'student':
            try:
                student = Student.objects.get(user=user)
                response_data['roll_number'] = student.roll_number
                response_data['department'] = student.department
                response_data['batch'] = student.batch
            except Student.DoesNotExist:
                pass

        elif user.role == 'teacher':
            try:
                teacher = Teacher.objects.get(user=user)
                response_data['employee_id'] = teacher.employee_id
                response_data['department'] = teacher.department
            except Teacher.DoesNotExist:
                pass

        return Response(response_data, status=status.HTTP_200_OK)


class RegisterView(APIView):

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)

        if not serializer.is_valid():
            return Response(
                serializer.errors,
                status=status.HTTP_400_BAD_REQUEST
            )

        user = serializer.save()
        tokens = get_tokens_for_user(user)

        return Response({
            'access_token': tokens['access'],
            'refresh_token': tokens['refresh'],
            'role': user.role,
            'name': f"{user.first_name} {user.last_name}",
            'username': user.username,
            'roll_number': user.student.roll_number,
            'department': user.student.department,
            'batch': user.student.batch,
        }, status=status.HTTP_201_CREATED)


class DeviceEnrollView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if request.user.role != 'student':
            return Response(
                {'error': 'Only students can enroll devices'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            student = Student.objects.get(user=request.user)
        except Student.DoesNotExist:
            return Response(
                {'error': 'Student record not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        public_key_str = request.data.get('public_key', '')
        device_fingerprint = request.data.get('device_fingerprint', '')

        # Validate public key format (PEM or DER)
        try:
            if public_key_str.startswith('-----'):
                load_pem_public_key(public_key_str.encode())
            else:
                der_bytes = base64.b64decode(public_key_str)
                load_der_public_key(der_bytes)
        except Exception:
            return Response(
                {'error': 'Invalid public key format'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Check if student already has a device enrolled
        existing_device = Device.objects.filter(student=student).first()

        if existing_device:
            # Re-enrollment: check hardware ID matches
            if existing_device.device_fingerprint != device_fingerprint:
                return Response(
                    {'error': 'This account is registered to a different device. Contact admin.'},
                    status=status.HTTP_403_FORBIDDEN
                )
            # Same device → update public key
            existing_device.public_key = public_key_str
            existing_device.save()
            return Response({
                'message': 'Device re-enrolled successfully',
                'device_fingerprint': existing_device.device_fingerprint,
                'enrolled_at': existing_device.registered_at,
            }, status=status.HTTP_201_CREATED)

        # First enrollment → create new device
        serializer = DeviceEnrollSerializer(
            data=request.data,
            context={'student': student}
        )

        if not serializer.is_valid():
            return Response(
                serializer.errors,
                status=status.HTTP_400_BAD_REQUEST
            )

        device = serializer.save(student=student)

        return Response({
            'message': 'Device enrolled successfully',
            'device_fingerprint': device.device_fingerprint,
            'enrolled_at': device.registered_at,
        }, status=status.HTTP_201_CREATED)


class DeviceStatusView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            student = Student.objects.get(user=request.user)
            device = Device.objects.get(student=student)
            return Response({
                'enrolled': True,
                'device_fingerprint': device.device_fingerprint,
                'enrolled_at': device.registered_at,
                'is_active': device.is_active,
            })
        except (Student.DoesNotExist, Device.DoesNotExist):
            return Response({
                'enrolled': False
            })