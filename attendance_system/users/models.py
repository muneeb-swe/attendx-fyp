from django.db import models
from django.contrib.auth.models import AbstractUser
from django.db.models import Q


class User(AbstractUser):
    ROLES = (
        ('student', 'Student'),
        ('teacher', 'Teacher'),
        ('admin', 'Admin'),
    )
    role = models.CharField(max_length=10, choices=ROLES)
    phone = models.CharField(max_length=15, blank=True)

    def __str__(self):
        return f"{self.username} ({self.role})"


class Student(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    roll_number = models.CharField(max_length=20, unique=True)
    department = models.CharField(max_length=100)
    batch = models.CharField(max_length=10)

    def __str__(self):
        return self.roll_number


class Teacher(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    department = models.CharField(max_length=100)
    employee_id = models.CharField(max_length=20, unique=True)

    def __str__(self):
        return self.user.get_full_name()


class Device(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='devices')
    public_key = models.TextField()
    device_fingerprint = models.CharField(max_length=255)
    registered_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            # One active device per student
            models.UniqueConstraint(
                fields=['student'],
                condition=Q(is_active=True),
                name='one_active_device_per_student'
            ),

            # One active student per physical device
            models.UniqueConstraint(
                fields=['device_fingerprint'],
                condition=Q(is_active=True),
                name='one_active_device_fingerprint'
            ),
        ]

    def __str__(self):
        return f"{self.student.roll_number} - {self.device_fingerprint[:20]}"
