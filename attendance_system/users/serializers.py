from rest_framework import serializers
from .models import User, Student, Teacher, Device


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()


class StudentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Student
        fields = ['roll_number', 'department', 'batch']


class TeacherSerializer(serializers.ModelSerializer):
    class Meta:
        model = Teacher
        fields = ['employee_id', 'department']


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'username', 'first_name', 'last_name', 'role', 'phone']


class DeviceEnrollSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ['public_key', 'device_fingerprint']

    def validate(self, data):
        # Only block on an ACTIVE device — a disabled device (e.g. after
        # a lost phone was deactivated by an admin) must not permanently
        # block the student from ever enrolling a replacement.
        student = self.context['student']
        if Device.objects.filter(student=student, is_active=True).exists():
            raise serializers.ValidationError(
                "Device already registered. Contact admin to replace."
            )
        return data