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
        # Check student doesn't already have a device
        student = self.context['student']
        if Device.objects.filter(student=student).exists():
            raise serializers.ValidationError(
                "Device already registered. Contact admin to replace."
            )
        return data