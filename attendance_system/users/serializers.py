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

class RegisterSerializer(serializers.ModelSerializer):
    roll_number = serializers.CharField()
    department = serializers.CharField()
    batch = serializers.CharField()
    password = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = [
            'username',
            'password',
            'first_name',
            'last_name',
            'phone',
            'roll_number',
            'department',
            'batch'
        ]

    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("Username already exists")
        return value

    def validate_roll_number(self, value):
        if Student.objects.filter(roll_number=value).exists():
            raise serializers.ValidationError("Roll number already registered")
        return value

    def create(self, validated_data):
        # Extract student specific fields
        roll_number = validated_data.pop('roll_number')
        department = validated_data.pop('department')
        batch = validated_data.pop('batch')

        # Create User
        user = User.objects.create_user(
            username=validated_data['username'],
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
            phone=validated_data.get('phone', ''),
            role='student'
        )

        # Create Student
        Student.objects.create(
            user=user,
            roll_number=roll_number,
            department=department,
            batch=batch
        )

        return user

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